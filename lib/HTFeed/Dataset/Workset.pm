package HTFeed::Dataset::Workset;

use warnings;
use strict;
use Carp;

use HTFeed::Config;

use JSON::Any;
use LWP::UserAgent;
use strict;
use XML::LibXML;

sub get_volumes {
    my $workset = shift;
    my $author = shift;

    my $token = get_access_token();
    my $id_string = get_id_list($workset,$author,$token);
    my @htids = split "\n", $id_string;

    return HTFeed::VolumeGroup->new(htids=>\@htids);
}

sub get_access_token {
    my $secret = get_config('dataset'=>'htrc_secret');
    
    my $request = HTTP::Request->new( POST => "https://silvermaple.pti.indiana.edu:9443/oauth2/token?grant_type=password" );
    $request->content_type( 'application/x-www-form-urlencoded' );
    $request->content( $secret );

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request( $request );

    my $j = JSON::Any->new;

    my $token;
    # evaluate the response
    if ( $response->is_success ) {
        my $json = $j->decode( $response->content );
        $token = $$json{access_token};
    }
    else { die $response->status_line }
    
    return $token;
}

sub get_id_list {
    my ($workset,$author,$token) = @_;
   
    my $header = HTTP::Headers->new;
    $header->header( 'Accept'  => 'application/vnd.htrc-workset+xml' );
    $header->header( 'Authorization' => 'Bearer '. $token );

    my $request   = HTTP::Request->new( 'GET', "https://silvermaple.pti.indiana.edu:9443/ExtensionAPI-1.1.1-SNAPSHOT/services/worksets/$workset/volumes.txt?author=$author" , $header );
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request( $request );

    # evaluate the response
    if ( $response->is_success ) { 
        return $response->content
    }
    else { die $response->status_line }
}

1;

__END__

=description

    get a VolumeGroup from an HTRC Workset

=cut
