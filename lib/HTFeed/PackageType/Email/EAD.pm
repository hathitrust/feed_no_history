package HTFeed::PackageType::Email::EAD;
use strict;

use HTFeed::PackageType::Email::EAD::Object;
use XML::LibXML;
use Carp qw(croak);

my $ns_EAD        = "urn:isbn:1-931666-22-9";
my $ns_prefix_EAD = "EAD";
my $schema_EAD    = "http://www.loc.gov/ead/ead.xsd";

sub new {
    my $class = shift;
    return bless {
        objects => [],
        events  => [],
    }, $class;
}

# Return the EAD node
sub to_node {
    my $self = shift;

    my $node = createElement("ead");

    foreach my $object ( @{ $self->{objects} } ) {
        $node->appendChild( objectOrNodeToNode($object) );
    }

    return $node;

}

# Create the element in the EAD namespace with the given name and text.
sub createElement {
    my $name = shift;
    my $text = shift;

    my $node = new XML::LibXML::Element($name);
    $node->setNamespace( $ns_EAD, $ns_prefix_EAD );

    if ( defined $text and !ref($text) ) {
        $node->appendText($text);
	}
    return $node;
}

sub objectOrNodeToNode {
    my $thing = shift;

    if ( ref($thing) =~ /^XML::LibXML/ ) {
        return $thing;
    }
    else {
        return $thing->to_node();
    }
}

sub add_object {
    my $self = shift;
    my $object = shift;

    push(@{$self->{'objects'}},$object);
}
sub add_event {
    my $self = shift;
    my $event = shift;

    push(@{$self->{'events'}},$event);
}
