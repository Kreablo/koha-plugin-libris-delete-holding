package Koha::Plugin::LibrisDeleteHolding::ApiConf;

use C4::Context;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw( all_apiconfs all_branch_mappings branch_mappings save_api_conf );

use strict;
use warnings;


sub all_apiconfs {
    my $plugin = shift;

    my $dbh = C4::Context->dbh;

    my $apiconf_table = $plugin->get_qualified_table_name('apiconfig');

    my $sth = $dbh->prepare("SELECT apiconf_name, client_id, client_secret FROM `$apiconf_table` ORDER BY apiconf_name ASC");

    my $ret = $sth->execute();

    return $sth->fetchall_arrayref({});
}

sub all_branch_mappings {
    my $plugin = shift;

    my $dbh = C4::Context->dbh;

    my $sigel_table = $plugin->get_qualified_table_name('sigel');

    my $sth = $dbh->prepare("SELECT branchcode, sigel, apiconf_name FROM `$sigel_table` ORDER BY branchcode ASC");

    my $ret = $sth->execute();

    return $sth->fetchall_arrayref({});
}

sub branch_mappings {
    my $plugin = shift;

    my $confs = all_apiconfs($plugin);
    my $mappings = all_branch_mappings($plugin);

    my %api_confs = ();
    my %branch_mappings_per_branchcode = ();
    my %branch_mappings_per_sigel = ();

    for my $conf (@$confs) {
        $api_confs{$conf->{apiconf_name}} = $conf;
    }

    for my $mapping (@$mappings) {
        $branch_mappings_per_branchcode{$mapping->{branchcode}} = {
            sigel => $mapping->{sigel},
            api_conf => $api_confs{$mapping->{apiconf_name}}
        };
        $branch_mappings_per_sigel{$mapping->{sigel}} = {
            api_conf => $api_confs{$mapping->{apiconf_name}}
        };
    }

    return {
        per_branchcode => \%branch_mappings_per_branchcode,
        per_sigel => \%branch_mappings_per_sigel
    };
}

sub save_api_conf {
    my $plugin = shift;
    my $cgi = shift;

    my $dbh = C4::Context->dbh;

    my $apiconf_table = $plugin->get_qualified_table_name('apiconfig');
    my $sigel_table = $plugin->get_qualified_table_name('sigel');

    $dbh->do("DELETE FROM `$sigel_table`;");
    $dbh->do("DELETE FROM `$apiconf_table`;");

    my %confs = ();
    my %mappings = ();

    my $add = sub {
        my ($h, $n, $k, $v) = @_;

        if (!exists $h->{$n}) {
            $h->{$n} = {};
        }

        $h->{$n}->{$k} = $v;
    };

    my $add_conf = sub {
        $add->(\%confs, @_);
    };

    my $add_mapping = sub {
        $add->(\%mappings, @_);
    };

    for my $c ($cgi->param) {
        my $p = $cgi->param($c);
        if ($c =~ /^credentials-name-(\d+)$/) {
            $add_conf->($1, 'name', $p);
        } elsif ($c =~ /^credentials-client-id-(\d+)$/) {
            $add_conf->($1, 'client_id', $p);
        } elsif ($c =~ /^credentials-client-secret-(\d+)$/) {
            $add_conf->($1, 'client_secret', $p);
        } elsif ($c =~ /^branch-mapping-branchcode-(\d+)$/) {
            $add_mapping->($1, 'branchcode', $p);
        } elsif ($c =~ /^branch-mapping-sigel-(\d+)$/) {
            $add_mapping->($1, 'sigel', $p);
        } elsif ($c =~ /^branch-mapping-credentials-(\d+)$/) {
            $add_mapping->($1, 'api_conf', $p);
        }
    }

    my @confs = keys %confs;
    @confs = sort { $a <=> $b } @confs;

    my @mappings = keys %mappings;
    @mappings = sort { $a <=> $b } @mappings;


    for my $n (@confs) {
        my $conf = $confs{$n};
        my $n = exists $conf->{name};
        my $id = exists $conf->{client_id};
        my $s = exists $conf->{client_secret};

        if (!($n && $id && $s)) {
            die "Api config is missing parameters:"
                . (!$n ? " 'name' is missing" : "")
                . (!$id ? " 'client_id' is missing" : "")
                . (!$s ? " 'client_secret' is missing" : "");
        }

        $dbh->do("INSERT INTO `$apiconf_table` (`apiconf_name`, `client_id`, `client_secret`) VALUES (?, ?, ?)",
                 {},
                 $conf->{name}, $conf->{client_id}, $conf->{client_secret});
    }

    for my $n (@mappings) {
        my $mapping = $mappings{$n};

        my $bc = exists $mapping->{branchcode};
        my $s = exists $mapping->{sigel};
        my $c = exists $mapping->{api_conf};

        if (!($bc && $s && $c)) {
            die "Branchcode mapping is missing parameters:"
                . (!$bc ? "'branchcode' is missing" : "")
                . (!$s ? "'sigel' is missing" : "")
                . (!$c ? "'api_conf' is missing" : "");
        }

        $dbh->do("INSERT INTO `$sigel_table` (`branchcode`, `sigel`, `apiconf_name`) VALUES (?, ?, ?)",
                 {},
                 $mapping->{branchcode}, $mapping->{sigel}, $mapping->{api_conf}
            );
    }

}

1;
