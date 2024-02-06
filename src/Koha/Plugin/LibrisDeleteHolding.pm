package Koha::Plugin::LibrisDeleteHolding;

use parent qw(Koha::Plugins::Base);
use Koha::Plugin::LibrisDeleteHolding::API qw(LIBRIS_PROD_MODE LIBRIS_QA_MODE LIBRIS_STG_MODE);
use Koha::Plugin::LibrisDeleteHolding::ApiConf qw(all_branch_mappings all_apiconfs save_api_conf );
use Koha::Plugin::LibrisDeleteHolding::Control qw( all_statuses_formatted process_item delete_items );

require Koha::Logger;
require Koha::Libraries;
require C4::Context;
require C4::Auth;
require C4::Languages;
require YAML::XS;

use strict;
use warnings;

our $VERSION = "1.0";

our $metadata = {
    name            => 'Libris Delete Holding Module',
    author          => 'Andreas Jonsson',
    date_authored   => '2023-12-15',
    date_updated    => "2024-02-06",
    minimum_version => 22.11,
    maximum_version => '',
    version         => $VERSION,
    description     => 'Automatic deletion of library holding in Libris XL when deleted in Koha.'
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    $self->{'class'} = $class;

    $self->{'logger'} = Koha::Logger->get;

    return $self;
}


sub install {
    my ( $self, $args ) = @_;

    my $dbh   = C4::Context->dbh;

    my $sigeltable = $self->get_qualified_table_name('sigel');
    my $apiconf = $self->get_qualified_table_name('apiconfig');
    my $statustable = $self->get_qualified_table_name('status');

    my $success = $dbh->do("CREATE TABLE IF NOT EXISTS `$apiconf` " . <<'EOF');
(
   apiconf_name VARCHAR(32) NOT NULL PRIMARY KEY,
   client_id VARCHAR(32) CHARSET ASCII NOT NULL,
   client_secret VARCHAR(512) CHARSET ASCII NOT NULL
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
EOF

    if (!$success) {
        return 0;
    }

    $success = $dbh->do("CREATE TABLE IF NOT EXISTS `$sigeltable` " . <<EOF);
(
   branchcode VARCHAR(10) PRIMARY KEY NOT NULL,
   sigel VARCHAR(10) NOT NULL,
   apiconf_name VARCHAR(32),
   INDEX (sigel),
   INDEX (apiconf_name),
   CONSTRAINT `${sigeltable}_fk1` FOREIGN KEY (branchcode) REFERENCES branches (branchcode) ON UPDATE CASCADE ON DELETE CASCADE,
   CONSTRAINT `${sigeltable}_fk2` FOREIGN KEY (apiconf_name) REFERENCES `$apiconf` (apiconf_name) ON UPDATE CASCADE
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
EOF

    if (!$success) {
        return 0;
    }

    $success = $dbh->do("CREATE TABLE IF NOT EXISTS `$statustable` " . <<EOF);
(
   id INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
   sigel VARCHAR(10) NOT NULL,
   record_id VARCHAR(64) NOT NULL,
   record_id_bib VARCHAR(32) NOT NULL,
   biblionumber INT,
   holding_id VARCHAR(64) NOT NULL,
   status ENUM('pending', 'done', 'cancelled', 'failed') NOT NULL,
   retries INT NOT NULL DEFAULT 0,
   timestamp TIMESTAMP NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
   INDEX (sigel),
   INDEX (record_id),
   INDEX (record_id_bib),
   INDEX (biblionumber),
   CONSTRAINT `${statustable}_fk1` FOREIGN KEY (sigel) REFERENCES `$sigeltable` (sigel) ON UPDATE CASCADE ON DELETE CASCADE,
   CONSTRAINT `${statustable}_fk2` FOREIGN KEY (biblionumber) REFERENCES biblio (biblionumber) ON UPDATE CASCADE ON DELETE SET NULL
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
EOF

    $self->store_data({ 'mode' => LIBRIS_PROD_MODE });

    unless ($self->retrieve_data('token')) {
        use Bytes::Random::Secure qw(random_bytes_base64);

        $self->store_data({'token' => random_bytes_base64(16, '')});
    }

    return $success;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $success = 1;

    return $success;
}

sub uninstall {
    my ( $self, $args ) = @_;

    my $success = 1;

    my $dbh = C4::Context->dbh;

    my $sigeltable = $self->get_qualified_table_name('sigel');
    my $apiconf = $self->get_qualified_table_name('apiconfig');
    my $statustable = $self->get_qualified_table_name('status');

    $dbh->do("DROP TABLE IF EXISTS `$statustable`");
    $dbh->do("DROP TABLE IF EXISTS `$sigeltable`");
    $dbh->do("DROP TABLE IF EXISTS `$apiconf`");

    return $success;
}


sub configure {
    my ( $self, $args ) = @_;

    my $methods = Koha::Plugins::Methods->search(
        {
            plugin_class => $self->{'class'}
        });

    my @errors = ();
    my $save_success = 0;

    while (my $method = $methods->next) {

        # The plugin manager by default exposes every method it finds
        # in this package and in the parent package.  We clean this up
        # when we configure the plugin.

        if (! grep {$_ eq $method->plugin_method} ('configure', 'install', 'uninstall', 'upgrade', 'enable', 'disable', 'tool', 'after_item_action', 'cronjob_nightly')) {
            $method->delete;
        }
    }

    my $token = $self->retrieve_data('token');
    my $cgi = $self->{'cgi'};

    if ( $cgi->request_method eq 'POST' && $cgi->param('save') && $cgi->param('token') eq $token) {
        my $dbh   = C4::Context->dbh;
        $dbh->{RaiseError} = 1;

        my $schema = Koha::Database->schema;

        eval {
            $schema->txn_do(sub {
                $self->store_data({
                    'mode' => scalar($cgi->param('libris_delete_holding_mode'))
                });

                save_api_conf($self, $cgi);
            });
        };

        if ($@) {
            my $msg = "Failed to save configuration: " . $@;

            $self->{'logger'}->error($msg);

            push @errors, $msg;
        } else {
            $save_success = 1;
        }
    }

    my $msg = $self->_load_messages($cgi);

    my $modes = [
        {
            mode => LIBRIS_PROD_MODE,
            label => $msg->{production_mode_label}
        },
        {
            mode => LIBRIS_QA_MODE,
            label => $msg->{qa_mode_label}
        },
        {
            mode => LIBRIS_STG_MODE,
            label => $msg->{stg_mode_label}
        }
    ];

    my $current_mode = $self->retrieve_data('mode');
    $current_mode = LIBRIS_PROD_MODE unless defined $current_mode;

    my $template = $self->get_template( { file => 'configure.tt' } );

    $template->param(
        MSG => $msg,
        config_js => $self->mbf_path('config.js'),
        token => $token,
        errors => \@errors,
        save_success => $save_success,
        libris_delete_holding_mode => $current_mode,
        libris_delete_holding_modes => $modes,
        branches => Koha::Libraries->search(undef, { order_by => { -asc => ['branchname'] }})->unblessed,
        branch_mappings => all_branch_mappings($self),
        credentials => all_apiconfs($self),
        can_configure => C4::Auth::haspermission(C4::Context->userenv->{'id'}, {'plugins' => 'configure'}),
        );

    $self->output_html( $template->output() );
}

sub _load_messages {
    my $self = shift;

    my $plugin_dir = $self->bundle_path;

    my $lang = C4::Languages::getlanguage($self->{'cgi'});
    my @lang_split = split /_|-/, $lang;

    my $default_msg = YAML::XS::LoadFile($plugin_dir . '/i18n/default.yml');
    my $lang_msg;

    for my $l ($lang, $lang_split[0]) {
        eval {
            $lang_msg = YAML::XS::LoadFile($plugin_dir . '/i18n/' . $l . '.yml');
        };
        if ($@) {
            last;
        }
    }

    if (!defined $lang_msg) {
        return $default_msg;
    }

    my $msg = {};

    for my $t (keys %$default_msg) {
        $msg->{$t} = exists $lang_msg->{$t} ? $lang_msg->{$t} : $default_msg->{$t};
    }

    return $msg;
}


sub after_item_action {
    my ($self, $params) = @_;

    my $action = $params->{action};
    my $item = $params->{item};
    my $item_id = $params->{item_id};

    $self->{logger}->debug('after_item_action action: "' . $action . '"');
    if ($action eq 'delete') {
        process_item($self, $item);
    }
}

sub cronjob_nightly {
    my $self = shift;

    $self->{logger}->debug('plugin_nightly');

    delete_items($self);
}

sub tool {
    my ($self) = @_;

    my $template = $self->get_template( { file => 'tool.tt' } );

    my $cgi = $self->{'cgi'};
    my $msg = $self->_load_messages($cgi);

    my $statuses = all_statuses_formatted($self, $msg);

    $template->param(
        MSG => $msg,
        statuses => $statuses
        );

    $self->output_html( $template->output() );
}

return 1;
