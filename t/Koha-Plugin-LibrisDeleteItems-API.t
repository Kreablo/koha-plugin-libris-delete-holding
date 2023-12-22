# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl SMS-Send-Driver-Infobip.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use utf8;
use strict;
use warnings;

use Test::More tests => 2;
BEGIN { use_ok('Koha::Plugin::LibrisDeleteItems::API') };

use Koha::Plugin::LibrisDeleteItems::API qw( LIBRIS_STG_MODE );

#

sub test_get_bearer {
    my $api = new Koha::Plugin::LibrisDeleteItems::API( LIBRIS_STG_MODE );

    my $client_id = '';
    my $client_secret = '';

    my $token = $api->_get_bearer($client_id, $client_secret);

    ok(length $token > 0, 'Got a token');

    return 0;
}

test_get_bearer();

1;
