package Koha::Plugin::LibrisDeleteHolding::API;

require JSON;
require Koha::Logger;
require Koha::Caches;
require HTTP::Request;
require Exporter;
require LWP::UserAgent;

use URI::Escape qw( uri_escape_utf8 );
use Koha::Plugin::LibrisDeleteHolding::ApiConf qw( all_apiconfs branch_mappings );

use strict;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(LIBRIS_PROD_MODE LIBRIS_QA_MODE LIBRIS_STG_MODE  get_api );

use constant {
    QA_URL    => 'https://libris-qa.kb.se',
    STG_URL   => 'https://libris-stg.kb.se',
    PROD_URL  => 'https://libris.kb.se',
    OAUTH_QA_URL => 'https://login-stg.libris.kb.se',  # login-stg is used also for QA
    OAUTH_STG_URL => 'https://login-stg.libris.kb.se',
    OAUTH_PROD_URL => 'https://login.libris.kb.se',
};

use constant {
    LIBRIS_PROD_MODE => 1,
    LIBRIS_QA_MODE   => 2,
    LIBRIS_STG_MODE  => 3
};

sub get_api {
    my $plugin = shift;

    return $plugin->{_api} if exists $plugin->{_api};

    $plugin->{_api} = new Koha::Plugin::LibrisDeleteHolding::API({
        mode => $plugin->retrieve_data('mode'),
        mappings => branch_mappings($plugin)
    });

    return $plugin->{_api};
}

sub _library_id {
    my $sigel = shift;

    return PROD_URL . '/library/' . $sigel;
}

sub _oauth_url {
    my $mode = shift;

    if ($mode == LIBRIS_PROD_MODE) {
        return OAUTH_PROD_URL;
    }

    if ($mode == LIBRIS_QA_MODE) {
        return OAUTH_QA_URL;
    }

    if ($mode == LIBRIS_STG_MODE) {
        return OAUTH_STG_URL;
    }
}

sub _api_url {
    my $mode = shift;

    if ($mode == LIBRIS_PROD_MODE) {
        return PROD_URL;
    }

    if ($mode == LIBRIS_QA_MODE) {
        return QA_URL;
    }

    if ($mode == LIBRIS_STG_MODE) {
        return STG_URL;
    }
}

sub new {
    my ($class, $params) = @_;

    my $mode = $params->{mode};

    my $self = {
        oauth_url => _oauth_url($mode),
        api_url => _api_url($mode),
        mode => $mode,
        agent => new LWP::UserAgent,
        mappings => $params->{mappings},
        logger => Koha::Logger->get({ 'category' => 'Koha::Plugin::LibrisDeleteItems::API' })
    };

    bless $self, $class;

    return $self;
}

sub _get_bearer {
    my ($self, $client_id, $client_secret) = @_;

    my $request = new HTTP::Request(POST => $self->{oauth_url}
                                    . '/oauth/token?client_id=' . uri_escape_utf8($client_id)
                                    . '&client_secret=' . uri_escape_utf8($client_secret)
                                    . '&grant_type=client_credentials');
    $request->header('Accept' => 'application/json');

    my $response = $self->{agent}->request($request);

    if ($response->code eq '200') {
        my $content = $response->content;
        my $json = new JSON;
        return $json->decode($content);
    }

    $self->{logger}->error('Failed to get bearer token, server replied ' . $response->code);

    die "Failed to get bearer token, " . $response->code . ".";
}

sub _initiate_privileged {
    my ($self, $request, $sigel) = @_;

    my $m = $self->{mappings}->{per_sigel};

    die "No mapping available for $sigel." unless exists $m->{$sigel};

    my $mapping = $m->{$sigel};
    my $c = $mapping->{api_conf};
    my $client_id = $c->{client_id};

    my $cache = Koha::Caches->get_instance('koha_plugin_librisdeleteitems');

    my $bearer = $cache->get_from_cache($client_id);

    if (!$bearer) {
        $bearer = $self->_get_bearer($client_id, $c->{client_secret});
        $cache->set_in_cache($client_id, $bearer, { expiry => $bearer->{"expires_in"} - 10 });
    }

    my $token = $bearer->{"access_token"};
    my $token_type = $bearer->{"token_type"};

    $request->header('Authorization', $token_type . ' ' . $token);
    $request->header('XL-Active-Sigel', $sigel);
}

sub delete_holding {
    my ($self, $holding_id, $sigel) = @_;

    my $request = new HTTP::Request(DELETE => $holding_id);
    $self->_initiate_privileged($request, $sigel);

    my $response = $self->{agent}->request($request);

    if ($response->code eq '200' || $response->code eq '204' || $response->code eq '404' || $response->code eq '410') {
        return 1;
    }

    return 0;
}

sub _get_record {
    my $self = shift;
    my $item_id = shift;

    my $request = new HTTP::Request(GET => $self->{api_url} . '/' . $item_id);
    $request->header('Accept' => 'application/json');

    my $response = $self->{agent}->request($request);

    if ($response->code eq '404') {
        $request = new HTTP::Request(GET => $self->{api_url} . '/resource/bib/' . $item_id);
        $request->header('Accept' => 'application/json');

        $response = $self->{agent}->request($request);
    }


    if ($response->code eq '200') {
        my $content = $response->content;
        my $json = new JSON;
        my $record = $json->decode($content);
        if ($record->{'@type'} eq 'Record') {
            return $record;
        }
    }

    return undef;
}

sub find_holding {
    my ($self, $sigel, $record_id) = @_;

    my $r = $self->_get_record($record_id);

    return undef if !defined $r;

    my $url = $self->{api_url} . '/_findhold?id=' . $r->{'@id'} . '&library=' . _library_id($sigel);

    $self->{logger}->debug('URL: ' . $url);
    my $request = new HTTP::Request(GET => $url);
    $request->header('Accept' => 'application/json');

    my $response = $self->{agent}->request($request);

    if ($response->code eq '200') {
        my $content = $response->content;
        my $json = new JSON;
        my $holdings = $json->decode($content);

        if (scalar(@{$holdings}) == 0) {
            return undef;
        }

        if (scalar(@{$holdings}) > 1) {
            $self->{logger}->warn("More than one holding for '$sigel' on record '" . $r->{'@id'});
        }

        return ($holdings, $r->{'@id'});
    }

    $self->{logger}->info("Failed to find holdings for record id " . $record_id . ": " . $response->code . ' ' . $response->message);

    return undef;
}

sub mappings {
    return $_[0]->{mappings};
}

return 1;
