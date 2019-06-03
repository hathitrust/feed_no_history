package HTFeed::PackageType::Email::EAD::Object;

use strict;
use base qw(HTFeed::PackageType::Email::EAD);

use XML::LibXML;
use XML::Parser;

sub new {
    my $class = shift;
    my $idtype = shift;
    my $id    = shift;
    return bless {
	idtype	   => $idtype,
        id         => $id,
        properties => []
    }, $class;
}

# create node for BHL EAD section
sub add_xml_file {
    my $self  = shift;
    my $file = shift;
	my $path = shift;

	my $ead = "$path/$file";

    my $prop_node = HTFeed::PackageType::Email::EAD::createElement("data");

	open(FILE, $ead) or die "$!";
	my @lines = (<FILE>);
	close(FILE);

	# remove redundant headers
	shift @lines;
	shift @lines;

	my $data_node = HTFeed::PackageType::Email::EAD::createElement("ead", "@lines");

	$prop_node->appendChild($data_node);
    
    push( @{ $self->{properties} }, $prop_node );
}

# Sets the preservation level to be output in the preservationLevel element
sub set_preservation_level {
    my $self               = shift;
    my $preservation_level = shift;

    $self->{'preservation_level'} = $preservation_level;
}

sub to_node {
    my $self = shift;

    my $node = HTFeed::PackageType::Email::EAD::createElement("object");
    if ( defined $self->{'id'} ) {
        my $identifier = HTFeed::PackageType::Email::EAD::createElement("objectIdentifier");
        $identifier->appendChild(
            HTFeed::PackageType::Email::EAD::createElement( "objectIdentifierType", $self->{'idtype'} ) );
        $identifier->appendChild(
            HTFeed::PackageType::Email::EAD::createElement( "objectIdentifierValue", $self->{'id'} ) );
        $node->appendChild($identifier);
    }

    foreach my $property ( @{ $self->{'properties'} } ) {
        $node->appendChild($property);
    }

    return $node;
}

1;
