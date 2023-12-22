use ExtUtils::MakeMaker;


WriteMakefile(
    NAME            => 'Koha::Plugin::LibrisDeleteItems',
    VERSION_FROM    => 'src/Koha/Plugin/LibrisDeleteItems.pm',
    NO_MYMETA       => 1
);

package MY;

sub dist {
    my $self = shift;
    my $text = $self->SUPER::dist(@_);

    $text .= <<'KPZ';

kpzdist: $(DISTVNAME).kpz

$(DISTVNAME).kpz: distdir
	rm -f ../../$(DISTVNAME).kpz
	cd $(DISTVNAME)/src && zip -r ../../$(DISTVNAME).kpz Koha/

.PHONY: kpzdist

KPZ
}
