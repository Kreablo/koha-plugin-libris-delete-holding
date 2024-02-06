package Koha::Plugin::LibrisDeleteHolding::Control;

use Koha::Plugin::LibrisDeleteHolding::API qw( get_api );
use C4::Context;
use Koha::DateUtils qw ( dt_from_string output_pref );

use strict;

use constant {
    MAX_RETRIES => 10
};

our @ISA = qw(Exporter);
our @EXPORT_OK = qw( all_statuses all_statuses_formatted process_item delete_items );

sub process_item {
    my $plugin = shift;
    my $item = shift;

    my $homebranch = $item->homebranch;
    my $api = get_api($plugin);
    my $mappings = $api->mappings->{per_branchcode};

    $plugin->{logger}->debug("process_item " . $item->itemnumber);

    if (!exists $mappings->{$homebranch}) {
        $plugin->{logger}->debug("No branchcode mapping for $homebranch.");
        return 0;
    }

    my $sigel = $mappings->{$homebranch}->{sigel};

    $plugin->{logger}->debug("sigel: $sigel");

    my $record_id_bib = _get_record_id($plugin, $item);

    $plugin->{logger}->debug("record_id_bib: " . $record_id_bib);

    if (scalar(grep { exists $mappings->{$_->{homebranch}} && $mappings->{$_->{homebranch}}->{sigel} eq $sigel } @{$item->biblio->items->unblessed}) <= 1) {
        my ($holdings, $record_id) = $api->find_holding($sigel, $record_id_bib);

        if (defined $holdings) {
            for my $holding (@$holdings) {
                $plugin->{logger}->debug('holding_id: ' . $holding);
                my $statustable = $plugin->get_qualified_table_name('status');

                C4::Context->dbh->do("INSERT INTO `$statustable` (sigel, record_id, record_id_bib, biblionumber, holding_id, status) VALUES (?, ?, ?, ?, ?, ?)",
                                     {},
                                     $sigel, $record_id, $record_id_bib, $item->biblio->biblionumber, $holding, 'pending');
            }
        }

    };
}

sub delete_items {
    my $plugin = shift;

    my $api = get_api($plugin);
    my $pending = all_pending($plugin);

    for my $i (@$pending) {

        my $engine = Koha::SearchEngine::Search->new({ index => $Koha::SearchEngine::BIBLIOS_INDEX });
        my ( $error, $results, $total_hits ) = $engine->simple_search_compat( _search_expr($i), 0, 1 );
        my $found = 0;
        SEARCH: for my $res (@$results) {
            my $biblionumber = $engine->extract_biblionumber( $results->[0] );
            my $items = Koha::Items->search({
                biblionumber => $biblionumber
            }, {
                distinct => 1
            });
            while (my $item = $items->next) {
                next if !exists $api->mappings->{$item->homebranch};
                my $m = $api->mappings->{$item->homebranch};
                if ($m->{sigel} eq $i->{sigel}) {
                    $found = 1;
                    last SEARCH;
                }
            }
        }

        if ($found) {
            _cancel($plugin, $i);
        } else {
            _delete($plugin, $api, $i);
        }
    }
}

sub _cancel {
    my ($plugin, $item) = @_;

    my $statustable = $plugin->get_qualified_table_name('status');

    C4::Context->dbh->do("UPDATE `$statustable` SET status = 'cancelled' WHERE id=?", {}, $item->{id});
}

sub _delete {
    my ($plugin, $api, $item) = @_;

    my $statustable = $plugin->get_qualified_table_name('status');

    if ($api->delete_holding($item->{holding_id}, $item->{sigel})) {
        C4::Context->dbh->do("UPDATE `$statustable` SET status = 'done' WHERE id=?", {}, $item->{id});
    } else {
        C4::Context->dbh->do("UPDATE `$statustable` SET status = 'failed', retries = retries + 1 WHERE id=?", {}, $item->{id});
    }
}

sub _get_record_id {
    my ($plugin, $item) = @_;

    my $biblio = $item->biblio;
    my $record = $biblio->record;

    my $f003 = $record->field('003');

    my $is_libris = $f003 && $f003->data() =~ m/^\s*SE-?LIBR\s*$/i;

    if (!$is_libris) {
        $plugin->{logger}->debug('Record ' . $biblio->biblionumber . ' is not a Libris record.');
        return undef;
    }

    my $f001 = $record->field('001');

    if (!$f001) {
        $plugin->{logger}->info('Record ' . $biblio->biblionumber . ' is missing controlfield 001');
        return undef;
    }

    return $f001->data();
}

sub all_statuses {
    my $plugin = shift;

    my $statustable = $plugin->get_qualified_table_name('status');

    my $sth = C4::Context->dbh->prepare("SELECT id, biblionumber, record_id, record_id_bib, holding_id, sigel, status, retries, timestamp FROM `$statustable` ORDER BY timestamp DESC");

    $sth->execute();

    return $sth->fetchall_arrayref({});
}

sub all_pending {
    my $plugin = shift;

    my $statustable = $plugin->get_qualified_table_name('status');

    my $sth = C4::Context->dbh->prepare("SELECT id, biblionumber, record_id, holding_id, sigel, status, retries, timestamp FROM `$statustable` WHERE status='pending' OR (status='failed' AND retries < ?) ORDER BY timestamp DESC");

    $sth->execute(MAX_RETRIES);

    return $sth->fetchall_arrayref({});
}

sub _search_expr {
    my $item = shift;

    my @parts = split '/', $_->{record_id};
    my $record_id = $parts[$#parts];

    return 'control-number,ext:' . $record_id . ($record_id ne $_->{record_id_bib} ? ' OR control-number,ext:' . $_->{record_id_bib} : '');
}

sub all_statuses_formatted {
    my $plugin = shift;
    my $msg = shift;

    my $statuses = all_statuses($plugin);

    my $status_msg = sub {
        my $status = shift;

        if ($status eq 'pending') {
            return $msg->{status_pending};
        }
        if ($status eq 'done') {
            return $msg->{status_done};
        }
        if ($status eq 'cancelled') {
            return $msg->{status_cancelled};
        }
        if ($status eq 'failed') {
            return $msg->{status_failed};
        }
        return $msg->{status_unknown};
    };

    my $bib_link_text = sub {
        my $biblionumber = shift->{biblionumber};
        my $biblionumber_link_text = $msg->{biblionumber_link_text};
        $biblionumber_link_text =~ s/%%/$biblionumber/g;
        return $biblionumber_link_text;
    };

    my @s = map {
        {
            biblionumber => $_->{biblionumber},
            biblionumber_link => '/cgi-bin/koha/catalogue/detail.pl?biblionumber=' . $_->{biblionumber},
            biblionumber_link_text => $bib_link_text->($_),
            record_id_bib_link => '/cgi-bin/koha/catalogue/search.pl?q=' . _search_expr($_),
            record_id_bib => $_->{record_id_bib},
            record_id => $_->{record_id},
            holding_id => $_->{holding_id},
            status => $status_msg->($_->{status}),
            timestamp => output_pref(dt_from_string($_->{timestamp}, 'sql')),
            retries => $_->{retries},
            sigel => $_->{sigel}
        }
    } @$statuses;

    return \@s;
}
