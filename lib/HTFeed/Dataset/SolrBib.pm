package HTFeed::Dataset::SolrBib;

use warnings;
use strict;
use Carp;
use v5.10;

use LWP::Simple;
use JSON::XS;
use URI::Escape;
use HTFeed::Config qw(get_config);

use Readonly;
Readonly::Scalar my $url_base => get_config('dataset'=>'solr_url_base'); # base url for solr query
Readonly::Scalar my $fields => 'id,ht_json'; # fields needed, this will only change if we need to get more metadata than just htid's
use constant PAGESIZE => 100000;

sub get_volumes{
    my $q = shift;
    $q = uri_escape($q);

    my @htids;

    my $page = 0;
    my $result = _do_query($q,$page,0);
    my $hit_count = $result->{response}{numFound};
    my $last_page = $hit_count / PAGESIZE;
    $last_page++
        if ($hit_count % PAGESIZE);

    # try to get around broken unicode issues
    my $ascii_json_decoder = JSON::XS->new->ascii(1);

    while ($page <= $last_page) {
        my $result = _do_query($q,$page);
        
        DOC:foreach my $doc (@{$result->{response}{docs}}) {
            my $id = $doc->{id};
            my $ht_json;
            # fiddle with broken UTF8
            eval { $ht_json = $ascii_json_decoder->decode($doc->{ht_json}); };
            croak "error decoding ht_json for bib id $id: $@"
                if ($@);
            foreach my $ht (@{$ht_json}) {
                my $htid = $ht->{htid};
                push @htids, $htid;
            }
        }
        # Increment for next time
        $page++;
    }

	return HTFeed::VolumeGroup->new(htids=>\@htids);
}

# _do_query($q,$page,$rows);
sub _do_query {
    my $q = shift;
    my $page = (shift // 0);
    my $rows = (shift // PAGESIZE);
    my $start = $rows * $page;

    # try to get around broken unicode issues
    my $ascii_json_decoder = JSON::XS->new->ascii(1);

    my $url = "$url_base?q=$q&rows=$rows&start=$start&wt=json&json.nl=arrarr&fl=$fields";
    return $ascii_json_decoder->decode(get($url));
}

1;

__END__

=description

    get a VolumeGroup from a Solr bib query

=cut
