# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl SMS-Send-Driver-Infobip.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use utf8;
use strict;
use warnings;

use Test::More tests => 2;
BEGIN { use_ok('Koha::Plugin::LibrisDeleteItems') };

require Koha::Cache::Memory::Lite;
use Cwd qw( abs_path );

#

sub test_load_messages {

    my $memory_cache = Koha::Cache::Memory::Lite->get_instance();
    my $cache_key = "getlanguage";
    my $cached = $memory_cache->get_from_cache($cache_key);

    $memory_cache->set_in_cache($cache_key, 'nonexisting_language');

    my $filename = $INC{'Koha/Plugin/LibrisDeleteItems.pm'};

    my $o = bless {
    }, 'Koha::Plugin::LibrisDeleteItems';

    $o->{_bundle_path} = abs_path($o->mbf_dir);

    my $msg = $o->_load_messages();

    ok(ref $msg eq 'HASH', 'Messages loaded');

    is($msg->{configuration}, 'Configuration');

    $memory_cache->set_in_cache($cache_key, 'sv-SE');

    $msg = $o->_load_messages();

    is($msg->{configuration}, 'Konfiguration');
    is($msg->{production_mode_label}, 'Production mode');

    if ($cached) {
        $memory_cache->set_in_cache($cache_key, $cached);
    } else {
        $memory_cache->clear_from_cache($cache_key);
    }

}

test_load_messages();

1;
