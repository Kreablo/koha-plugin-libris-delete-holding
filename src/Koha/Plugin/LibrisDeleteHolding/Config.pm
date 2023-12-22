package Koha::Plugin::LibrisDeleteHolding::Config;

sub new {
    my $class = shift;

    my $self = {
        sigel_map => new SigelMap(),
        sigel_conf => new SigelConf()
    };

    return bless $class, $self;
};



return 1;
