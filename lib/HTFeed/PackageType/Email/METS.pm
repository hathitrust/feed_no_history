package HTFeed::PackageType::Email::METS;

use strict;
use warnings;
use PREMIS;
use HTFeed::XMLNamespaces qw(:namespaces :schemas register_namespaces);
use Carp;
use Cwd qw(cwd abs_path);
use HTFeed::Config qw(get_config);
use File::Basename qw(basename dirname);
use File::Copy;
use FindBin;
use File::Copy;
use MIME::Types;
use Data::Dumper qw(Dumper);
use XML::LibXML qw(:libxml);
use base qw(HTFeed::METS);

sub new {
	my $class = shift;
	my $self  = $class->SUPER::new( @_, );
	$self->{outfile} = $self->{volume}->get_mets_path();

	return $self;
}

sub run {
	my $self = shift;
	my $mets = new METS( objid => $self->{volume}->get_identifier() );
	$self->{'mets'}	= $mets;
	$self->{'amdsecs'} = [];
	$self->{'dmdsecs'} = [];
	$self->{filegroups} = {};

	$self->_add_schemas();
	$self->_add_header();
	$self->_add_dmdsecs();
	$self->_add_filesecs();
	$self->_add_struct_map();
	$self->_add_amdsecs();
	$self->_save_mets();
	$self->_validate_mets();
	$self->_set_done();
}

sub stage_info {
	return { success_state => 'metsed', failure_state => 'punted' };
}

# PREMIS and EAD each require defined schema
sub _add_schemas {
	my $self = shift;
	my $mets = $self->{mets};

	$mets->add_schema( "PREMIS", NS_PREMIS, SCHEMA_PREMIS);
	$mets->add_schema( "EAD",	NS_EAD,	SCHEMA_EAD );
}

sub _add_header {
	my $self = shift;
	my $mets = $self->{mets};

	my $header = new METS::Header(
		createdate   => $self->_get_createdate(),
		recordstatus => 'NEW',
		id		   => 'HDR1',
	);
	$header->add_agent(
		role => 'CREATOR',
		type => 'ORGANIZATION',
		name => 'DLPS'
	);

	$mets->set_header($header);

	return $header;
}

sub _add_dmdsecs {
	my $self = shift;
	$self->_add_ead();
	$self->{'mets'}->add_dmd_sec(@{ $self->{dmd_mdsecs} } );
}

# Wrap the EAD section
sub _add_ead {
	sub add_namespace {
		my $node = shift;
		$node->setNamespace(NS_EAD,'EAD');
		foreach my $child ($node->childNodes()) {
			add_namespace($child) if $child->nodeType() == XML_ELEMENT_NODE;
		}
    }

	my $self   = shift;
	my $volume = $self->{volume};
	my $nspkg = $volume->get_nspkg();

	my $ead_file = $volume->get_ead();

	my $path = $volume->get_staging_directory();

	my $dmdsec =
		new METS::MetadataSection( 'dmdSec', id => 'DMD1' );

    my $parser = new XML::LibXML;

    my $parsed_xml = $parser->parse_file( "$path/$ead_file");

	# set namespace of all nodes to the EAD namespace
	add_namespace($parsed_xml->documentElement());

    $dmdsec->set_xml_node($parsed_xml->documentElement(),mdtype => 'EAD');

	push( @{ $self->{dmd_mdsecs} }, $dmdsec );

}

sub _add_content_fgs{
	return;
}

# reads in premis events from a CSV whose columns are identified by the first line
sub _add_source_premis_events {
	my $self = shift;
    my $premis = $self->{premis};
	my $volume = $self->{volume};

	my $source_premis = $volume->get_source_premis();
	my $path = $volume->get_staging_directory();

	open(FILE, "$path/$source_premis") || die ("can't open file");
    my $headers = <FILE>; 
    $headers =~ s/[\r\n]+//g;
    my @headers = split(',',$headers);

	foreach my $line(<FILE>){
        $line =~ s/[\r\n]+//g;
        next if $line =~ /^\s*$/; # ignore blank lines
        my %eventinfo = ();
        my %linking_agent = ();
        my @linking_agents = ();
        my @eventfields = split(',',$line);
        foreach my $header (@headers) {
            if($header =~ /^linkingAgent/) {
                # if we repeat headers, start a new linking agent
                if(defined $linking_agent{$header}) {
                    push(@linking_agents,{%linking_agent});
                    %linking_agent = ();
                }
                $linking_agent{$header} = shift(@eventfields);
            } else {
                $eventinfo{$header} = shift(@eventfields);
            }
        }
        # make sure to use the last linking agent, if there were any fields for it.
        push(@linking_agents,{%linking_agent}) if(keys(%linking_agent));

        foreach my $required_field (qw(eventIdentifierValue eventIdentifierType eventType eventDateTime eventDetail)) {
            if(not defined $eventinfo{$required_field}) {
                $self->set_error("BadField",field=>$required_field,detail=>"Incomplete source PREMIS event ",actual => Dumper(\%eventinfo));
            }
        }

        my $event = new PREMIS::Event(
            $eventinfo{eventIdentifierValue},
            $eventinfo{eventIdentifierType},
            $eventinfo{eventType},
            # dates generated w/o time zone info by the Bentley
            $self->convert_tz($eventinfo{eventDateTime},'America/Detroit'), 
            $eventinfo{eventDetail}
        );

        foreach my $linking_agent (@linking_agents) {
            $event->add_linking_agent(
                new PREMIS::LinkingAgent(
                $linking_agent->{linkingAgentIdentifierType},
                $linking_agent->{linkingAgentIdentifierValue},
                $linking_agent->{linkingAgentRole}
            ));
        }
        
        $premis->add_event($event);

	}
	
	close(FILE);
}


sub _add_premis {
	my $self   = shift;
	my $volume = $self->{volume};
	my $nspkg = $volume->get_nspkg();

	$self->{included_events} = {};

	my $premis = new PREMIS;
	$self->{premis} = $premis;

	# create PREMIS object
	my $premis_object =
		new PREMIS::Object( 'identifier', $volume->get_identifier() );
	$premis_object->set_preservation_level("1");

	$premis_object->add_significant_property ('file count',
			$volume->get_file_count() );
	$premis->add_object($premis_object);

	$volume->record_premis_event('ingestion');

	# add BHL PREMIS from PREMIS file
	$self->_add_source_premis_events();

	# Add local PREMIS events
	$self->_add_premis_events( $nspkg->get('premis_events') );

	my $digiprovMD =
		new METS::MetadataSection( 'digiprovMD', 'id' => 'premis1' );
	$digiprovMD->set_xml_node( $premis->to_node(), mdtype => 'PREMIS');

	push( @{ $self->{amd_mdsecs} }, $digiprovMD );

}


sub _add_amdsecs {
	my $self = shift;

	$self->_add_premis();

	$self->{'mets'}->add_amd_sec( $self->_get_subsec_id("AMD"), @{ $self->{amd_mdsecs} } );
}

sub _add_filesecs {

	my $self= shift;

	$self->_add_zip_fg();
	$self->_add_mbox_filegroup();
	$self->_add_attachments();
	$self->_add_supplements();
}

sub _add_zip_fg {
    my $self = shift;
    my $mets   = $self->{mets};
    my $volume = $self->{volume};

    $volume->record_premis_event('zip_md5_create');
    my $zip_filegroup = new METS::FileGroup(
        id  => $self->_get_subsec_id("FG"),
        use => 'zip archive'
    );

    my $objid = $volume->get_objid();
    my $zip_directory =  get_config('staging'=>'zipfile');
    foreach my $zip_file (glob("$zip_directory/$objid/*zip")) {
        $zip_filegroup->add_file( basename($zip_file), path => dirname($zip_file), prefix => 'ZIP' );
    }
	$self->{filegroups}{'zip'} = $zip_filegroup;
    $mets->add_filegroup($zip_filegroup);
}

sub _add_mbox_filegroup{
	my $self = shift;
	my $mets = $self->{mets};
	my $volume = $self->{volume};

	my $filegroups = $volume->get_file_groups();

	my @mboxes = $volume->get_mbox_files();
	return if (!@mboxes);

	while ( my ( $filegroup_name, $filegroup ) = each(%$filegroups) ) {

		next unless($filegroup_name eq "mbox");

		my $mets_filegroup = new METS::FileGroup(
			id  => $self->_get_subsec_id("FG"),
			use => $filegroup->get_use()
		);

        foreach my $full_mbox_path (@mboxes) {
            my $mbox = basename($full_mbox_path);
            my $mboxdir = dirname($full_mbox_path);

			$mets_filegroup->add_file(
				$mbox,
				path => $mboxdir,
				prefix => $filegroup->get_prefix(),
				mimetype => "application/mbox",
			);
		}

		$self->{filegroups}{$filegroup_name} = $mets_filegroup;
		$mets->add_filegroup($mets_filegroup);
	}
}

sub _add_supplements {

	my $self = shift;
	my $mets = $self->{mets};
	my $volume = $self->{volume};

	my @supp = $volume->get_supplementary_files();

	return if (!@supp);

	my $mets_filegroup = new METS::FileGroup(
		id => $self->_get_subsec_id("FG"),
		use => "supplements", 
	);

    foreach my $supp (@supp) {
        my $file = basename($supp);
        my $dir = dirname($supp);

		$mets_filegroup->add_file(
			$file,
			path => $dir,
			prefix => "SUPP",
			mimetype => $self->get_mimetype($file),
		);
	}

	$self->{filegroups}{'supplements'} = $mets_filegroup;
	$mets->add_filegroup($mets_filegroup);
}

sub _add_attachments {

	my $self = shift;
	my $mets = $self->{mets};
	my $volume = $self->{volume};
	my $date = "";
	my $ID = "";


	my %files = $volume->get_attachment_files();
	return if(!%files);

	my $path = $volume->get_staging_directory();

	my $mets_filegroup = new METS::FileGroup(
		id  => $self->_get_subsec_id("FG"),
		use => "attachments",
	);

	foreach my $file(sort keys %files){

		$mets_filegroup->add_file(
			$file,
			path => $files{$file},
			mimetype => $self->get_mimetype($file),
			prefix => 'ATT',
		);

	}

	$self->{filegroups}{'attachments'} = $mets_filegroup;
	$mets->add_filegroup($mets_filegroup);
}

sub _add_struct_map {
	my $self   = shift;
	my $mets   = $self->{mets};
	my $volume = $self->{volume};
	my @attachments;

	my $dir = $volume->get_staging_directory();

	my $struct_map = new METS::StructMap( id => 'SM1', type => 'physical' );
	my $voldiv = new METS::StructMap::Div( type => 'deposit' );

	$struct_map->add_div($voldiv);

	my $order = 1;

	# Generate a section for each submission
	my @submissions = $volume->get_submissions();
	foreach my $sub(@submissions){

		my @mboxes = $volume->get_mbox_files_by_sub($sub);
        my @mboxinfo = ();

        if(!@mboxes) {
            $self->set_error("MissingFile",detail=>"No mboxes found for $sub");
        }

		# ID mboxes & attachments
        foreach my $mbox (@mboxes) {
            my $mboxinfo = {};
            my $mboxdir = dirname($mbox);

            $mboxinfo->{label} = basename($mbox);
            $mboxinfo->{path} = $mbox;
            $mboxinfo->{zip} = $volume->get_zip_for_mbox($mbox);

            my $supplement = $volume->get_supplement_for_mbox($mbox);
            if(defined $supplement and $supplement) {
                $mboxinfo->{supplement} = basename($supplement);
                $mboxinfo->{supplement_zip} = $volume->get_zip_for_mbox($supplement);
            }
			my $attach_dir = $mbox . "_attachments";
            if(-d $attach_dir){
            	#get attachments
                opendir(DIR, $attach_dir) || die "Can't open dir $attach_dir: $!\n";
                foreach my $att(readdir(DIR)) {
                    next if($att =~ /^\.+$/);
					#add value $att to hash of $mbox keys
					push(@{$mboxinfo->{attachments}},$att);
				}
			}
            push(@mboxinfo,$mboxinfo);
		}

		$voldiv->add_div(
			$self->sub_div(
				\@mboxinfo,
				label => $sub,
				order => $order++,
				type => 'submission',
			),
		);

	}
	$mets->add_struct_map($struct_map);
}

sub sub_div {
    my $self    	= shift;
	my $mboxes 		= shift;
    my %attrs   	= @_;
    my $div     	= METS::StructMap::Div->new(%attrs);

	my $order = 1;

    foreach my $mbox (@$mboxes) {

        $div->add_div(
            $self->mbox_div(
                $mbox,
                label => $mbox->{label},
                order => $order,
                type => 'mbox',
            ),
        );
        $order++;
    }

	return $div;
}

sub mbox_div {
   my $self    = shift;
   my $mbox = shift;
   my $volume = $self->{volume};
    my %attrs   = @_;
    my $div     = METS::StructMap::Div->new(%attrs);

    $div->add_fptr( fileid => $self->{filegroups}{zip}->get_file_id($mbox->{zip}) );

    # also add a fileid for the zipped PST
    if(defined $mbox->{supplement_zip}) {
        $div->add_fptr( fileid => $self->{filegroups}{zip}->get_file_id($mbox->{supplement_zip}) ); 
    }

	$div->add_div(
		$self->add_mboxfile_div($attrs{label},$mbox->{supplement})
	);

	if(defined $mbox->{attachments}){
		$div->add_div(
			$self->attachment_div($mbox->{attachments})
		);
	}

	return $div;
}


sub add_mboxfile_div {

	my $self = shift;
	my $mbox = shift;
    my $pst = shift;
    my $volume = $self->{volume};

	my $div = METS::StructMap::Div->new(type => 'mboxfile');

	$div->add_fptr( fileid => $self->{filegroups}{mbox}->get_file_id($mbox));
    if(defined $pst) {
        $div->add_fptr( fileid => $self->{filegroups}{supplements}->get_file_id($pst));
    }

	return $div;

}

sub attachment_div {

	my $self    = shift;
    my $attachments = shift;
    my %attrs   = @_;

	my $div = METS::StructMap::Div->new(type => 'attachments');

    my @sorted_attachments = sort @$attachments;

	foreach my $att (@sorted_attachments) {

		$div->add_div(
			$self->add_attachment_div($att)
		);
	}

	return $div;

}

sub add_attachment_div {

	my $self = shift;
	my $att = shift;

	my $div = METS::StructMap::Div->new(type => 'attachment');

	$div->add_fptr( fileid => $self->{filegroups}{attachments}->get_file_id($att));

	return $div;

}

sub get_mimetype {
    my $self = shift;
    my $filename = shift;
    my ($suffix) = ($filename =~ /\.([^.]+)$/);

	if($suffix eq "mbox"){
		return "application/mbox";
	}

	my $mime_types = MIME::Types->new;
	my $mime_type = $mime_types->mimeTypeOf($suffix);

    if(defined $suffix and defined $mime_type) {
		return $mime_type;
    } else {
		return 'application/octet-stream';
    }
}

# don't clean yet...
# or allow main METS class to clean
# but generate manifest /first/ as
# part of the METS stage process
sub clean_always {
    my $self = shift;
	return;
}

1;
