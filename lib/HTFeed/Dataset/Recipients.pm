package HTFeed::Dataset::Recipients;

use warnings;
use strict;
use 5.10.1;

use LWP::Simple;
use JSON::Any;

my $mail_list_url = 'https://spreadsheets.google.com/a/umich.edu/tq?tqx=out:json&tq=select+C,O&key=0Ag4T93aUS_BTdEU0cXNHYjVKeE9IRUNFUl9QMGJ5RGc';

sub get_recipient_map {
    # get mail list from google docs
    my $mail_list = get $mail_list_url;

    # clean off js from json doc
    my $preamble = "google.visualization.Query.setResponse(";
    my $i = index $mail_list, $preamble;
    die 'JSON file not in expected format' unless $i == 0 and $mail_list =~ s/\);$//;
    $mail_list = substr $mail_list, length($preamble);

    # extract data from json
    my $mail_list_hash = JSON::Any->decode($mail_list);

    # find correct columns
    my $email_col_label = 'Email';
    my $dataset_col_label = 'Dataset Normalized';
    my $email_col;
    my $dataset_col;

    foreach my $col (0..$#{$mail_list_hash->{'table'}->{'cols'}}) {
        my $label = $mail_list_hash->{'table'}->{'cols'}->[$col]->{'label'};
        $email_col = $col
            if ($label eq $email_col_label);
        $dataset_col = $col
            if ($label eq $dataset_col_label);
    }
    (defined $dataset_col and defined $email_col) or die 'Needed columns in JSON not found';

    my $dataset_hash = {};
    foreach my $row (@{$mail_list_hash->{'table'}->{'rows'}}) {
        my $email_str = _clean($row->{'c'}->[$email_col]->{'v'});
        # ignore null email address
        next unless $email_str;
        my $dataset_str = _clean($row->{'c'}->[$dataset_col]->{'v'});
        # ignore null and "none" dataset names
        next unless $dataset_str;
        next if ($dataset_str eq 'none');

        foreach my $address (split ' ',$email_str) {
            foreach my $dataset (split ' ',$dataset_str) {
                $dataset_hash->{$dataset} //= {};
                ($dataset_hash->{$dataset}->{$address})++;
            }
        }
    }

    return $dataset_hash;
}

sub _clean {
    my $str = shift;
    $str =~ s/,/ /g;
    $str =~ s/\s+/ /g;
    chomp $str;
    return $str;
}

1;

__END__

