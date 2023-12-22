package Koha::Plugin::LibrisDeleteHolding::Control;

use Koha::Plugin::LibrisDeleteHolding::API qw( get_api all_statuses all_statuses_formatted );
use C4::Context;
use Koha::DateUtils qw ( dt_from_string output_pref );


sub process_item {
    my $plugin = shift;
    my $item = shift;

    my $homebranch = $item->homebranch;
    my $api = get_api($plugin);
    my $mappings = $api->mappings;

    if (!exists $mappings->{$homebranch}) {
        $self->{logger}->debug("No branchcode mapping for $branchcode.");
        return 0;
    }

    my $sigel = $mappings->{$homebranch}->{sigel};

    my $record_id_bib = _get_record_id($item);

    if (scalar(grep { exists $mappings->{$_->homebranch} && $mappings->{$_->homebranch}->{sigel} eq $sigel } @{$item->biblio->items}) <= 1) {
        my $holding = $api->find_holding($sigel, $record_id_bib);

        if (defined $holding) {
            my $statustable = $self->get_qualified_table_name('status');

            C4::Context->dbh->do("INSERT INTO `$statustable` (sigel, record_id, record_id_bib, biblionumber, holding_id, status) VALUES (?, ?, ?, ?, ?, ?)",
                                 {},
                                 $sigel, $record_id, $record_id_bib, $item->biblio->biblionumber, $holding, 'pending');
        }

    };
}

sub _get_record_id {
    my ($item) = @_;

    my $biblio = $item->biblio;
    my $record = $biblio->record;

    my $f003 = $record->field('003');

    my $is_libris = $f003 && $f003->data() =~ m/^\s*SE-?LIBR\s*$/i;

    if (!$is_libris) {
        $self->{logger}->debug('Record ' . $biblio->biblionumber . ' is not a Libris record.');
        return undef;
    }

    my $f001 = $record->field('001');

    if (!$f001) {
        $self->{logger}->info('Record ' . $biblio->biblionumber . ' is missing controlfield 001');
        return undef;
    }

    return $f001->data();
}

sub all_statuses {
    my $plugin = shift;

    my $statustable = $self->get_qualified_table_name('status');

    my $sth = C4::Context->dbh->prepare('SELECT biblionumber, record_id, sigel, status, retries, timestamp FROM `$statustable` ORDER BY timestamp DESC');

    $sth->execute();

    $sth->fetchall_arrayref({}));
}



sub all_statuses_formatted {
    my $plugin = shift;
    my $msg = shift;

    my $statuses = all_statuses($plugin);

    my $status_msg = sub {
        my $status = shift;

        if ($status eq 'pending') {
            return $msg.status_pending;
        }
        if ($status eq 'done') {
            return $msg.status_done;
        }
        return $msg.status_unknown;
    };

    my $biblionumber_link_text = $msg->{biblionumber_link_text};

    $biblionumber_link_text =~ s/%%/$biblionumber/g;


    my @s = map {
        biblionumber => $_->{biblionumber},
        biblionumber_link => '/cgi-bin/koha/catalogue/detail.pl?biblionumber=' . $_->{biblionumber},
        biblionumber_link_text => $biblionumber_link_text,
        record_id_bib_link => '/cgi-bin/koha/catalogue/search.pl?q=control-number,ext:' . $_->{record_id_bib},
        record_id_bib => $_->{record_id_bib},
        record_id => $_->{record_id},
        holding_id => $_->{holding_id},
        status => $status_msg->($_->{status}),
        timestamp => output_pref(dt_from_string($_->{timestamp}, 'sql')),
        retries => $_->{retries},
        sigel => $_->{sigel}
    } @$statuses;

    return \@s;
}
