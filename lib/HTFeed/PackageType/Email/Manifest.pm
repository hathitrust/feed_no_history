package HTFeed::PackageType::Email::Manifest;

use strict;
use warnings;
use HTFeed::Config qw(get_config);
use base qw(HTFeed::Stage);
use File::Basename qw(basename dirname);

# Process the submission package manifest
# into a DC manifest containing additional
# package info for Deep Blue

sub new {
	my $class = shift;
	my $self  = $class->SUPER::new( @_, );
	$self->{outfile} = $self->{volume}->get_manifest_path();

	return $self;
}

sub stage_info {
    return { success_state => 'manifested', failure_state => 'punted' };
}

sub run {

	my $self = shift;
	my $volume = $self->{volume};
    my $objid = $volume->get_objid();

    my $orig_manifest_xpc = $volume->get_manifest_xpc();
	# get manifest file
	my $path = get_config('staging' => 'ingest');
	my $newManifest = "$path/$objid.manifest.xml";

    my $manifest_dom = XML::LibXML::Document->new("1.0","UTF-8");
    # only include zip files
    my $item = $manifest_dom->createElement("item");
    $item->setAttribute("identifier.other",$objid);

    my $orig_manifest_item = ($orig_manifest_xpc->findnodes("/item"))[0];
    foreach my $attribute (qw(collectionHandle dc.identifier.other dc.title
        dc.description.abstract dc.type dc.contributor.author
        dc.contributor.other dc.date.created dc.coverage.temporal
        dc.date.issued dc.rights.access dc.date.open dc.rights.copyright)) {
        my $value = $orig_manifest_item->getAttribute($attribute);
        if(defined $value) {
            $item->setAttribute($attribute,$value);
        } else {
            warn("Attribute $attribute not found!");
        }
    }

    $manifest_dom->setDocumentElement($item);

    my $zip_directory =  get_config('staging'=>'zipfile');
    foreach my $zip_file (glob("$zip_directory/$objid/*zip")) {
        my $file = new METS::File();
        $file->set_local_file(basename($zip_file),dirname($zip_file));
        my $extent = $file->{attrs}{SIZE};
        $file->compute_md5_checksum();
        my $checksum = $file->{attrs}{CHECKSUM};

        my $basename = basename($zip_file);

        my $bitstream = $manifest_dom->createElement("bitstream");
        $bitstream->setAttribute("dc.title.filename",$basename);
        $bitstream->setAttribute("dc.description.md5.checksum",$checksum);
        $bitstream->setAttribute("dc.format.mimetype","application/zip");
        $bitstream->setAttribute("dc.extent",$extent);

        # copy attributes from original manifest
        my $mbox = basename($volume->get_mbox_for_zip($basename));
        my $orig_manifest_bitstream = ($orig_manifest_xpc->findnodes('//bitstream[@dc.title.filename="' . $mbox . '"]'))[0];
        die("Can't find mbox $mbox") unless defined $orig_manifest_bitstream;
        foreach my $attribute (qw(dc.description.filename dc.date.created dc.coverage.temporal)) {
            $bitstream->setAttribute($attribute,$orig_manifest_bitstream->getAttribute($attribute));
        }

        $item->appendChild($bitstream);

    }

	open(OUT, ">$newManifest") or  die("Can't open $newManifest: $!");
    print OUT $manifest_dom->toString(1);
    close(OUT);

	$self->_set_done();

}

1;
