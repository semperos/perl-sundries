#!/usr/bin/env perl
#
# Usage: redis-sample <file-of-scores>
#
# Example of hitting redis and doing some basic rollups on data.
#

use strict;
use warnings;
use 5.10.0;

die "Usage: $0 <channel-name> <city-id> <num-records>\n" if @ARGV < 3;

sub format_file_name{
    my ($channel, $city_id, $suffix) = @_;
    return "foo_${channel}_${city_id}_${suffix}.txt";
}

my $host = "http://example.com"
my @key_rows;
sub get_keys{
    my ($channel, $city_id, $keys_file, $num_records) = @_;
    if (-e $keys_file) {
        print("Reading Redis keys from file $keys_file.\n");
        open my $keys_fh, '<', $keys_file or die "Could not open file $keys_file for reading.\n";
        chomp(@key_rows = <$keys_fh>);
        close $keys_fh;
    } else {
        my $key_pattern = "$channel:city:$city_id:person:*";
        print("Querying keys '$key_pattern' and writing to $keys_file...\n");
        @key_rows = qx(/opt/redis/bin/redis-cli -h $host -p 6382 keys $key_pattern | head -$num_records);
        open my $keys_fh, '>', $keys_file or die "Could not open $keys_file for writing.\n";
        print $keys_fh @key_rows;
        close $keys_fh;
    }
    @key_rows = grep { $_ ne "" } @key_rows;
    die "No keys found for $channel city $city_id in $keys_file.\n" unless @key_rows;
}

my @score_rows;
sub get_scores {
    my $scores_file = shift;
    if (-e $scores_file) {
        print("Reading scores from $scores_file.\n");
        open my $scores_fh, '<', $scores_file or die "Could not open file $scores_file for reading.\n";
        chomp(@score_rows = <$scores_fh>);
        close $scores_fh;
    } else {
        if (@key_rows) {
            print("Writing scores for " . @key_rows . " keys to $scores_file.\n");
            foreach my $i (0 .. $#key_rows) {
                my $key = $key_rows[$i];
                $score_rows[$i] = qx(/opt/redis/bin/redis-cli -h $host -p 6382 get "$key");
            }
            open my $scores_fh, '>', $scores_file or die "Could not open $scores_file for writing.\n";
            print $scores_fh @score_rows;
            close $scores_fh;
        } else {
            die "Keys array empty. Call get_keys() first.\n";
        }
    }
    @score_rows = grep { $_ ne "" } @score_rows;
    die "No scores found.\n" unless @score_rows;
}

sub print_heading{
    my ($heading, $sep) = @_;
    print("\n" . $heading . "\n" . "$sep"x(length($heading)) . "\n");
}

sub print_freqs{
    my %report = %{shift()};
    my $key = shift;
    my $prefix = shift;

    foreach (sort keys(%{$report{$key}})) {
        print("$prefix '" . $_ . "'\t: " . $report{$key}{$_} . " times\n");
    }
}

sub print_scoring_report{
    my ($channel, $city_id) = @_;
    my @scores = @score_rows;
    print_heading("Scoring Report", "=");
    my %report;
    foreach (@scores) {
        if ( my ($inventory_type, $tier, $group, $model, $last_transform, $raw_items) = /([^\+]+)\+([^\+]+)\+([^\+]+)\+([^\+]+)\+([^\+]+):(.*)/ ) {
            $report{"inventory_types"}{$inventory_type} += 1;
            $report{"tiers"}{$tier} += 1;
            $report{"groups"}{$group} += 1;
            $report{"models"}{$model} += 1;
            $report{"last_transforms"}{$last_transform} += 1;
            if ( $raw_items =~ /^([dotpc][0-9]+)\s([dotpc][0-9]+)\s([dotpc][0-9]+)\s.*/ ) {
                $report{"first_items"}{$1} += 1;
                $report{"second_items"}{$2} += 1;
                $report{"third_items"}{$3} += 1;
            }
        }
    }
    print_heading("1st Position Items", "-");
    print_freqs(\%report, "first_items", "Item");

    print_heading("2nd Position Items", "-");
    print_freqs(\%report, "second_items", "Item");

    print_heading("3rd Position Items", "-");
    print_freqs(\%report, "third_items", "Item");

    print_heading("Scoring Metadata", "-");
    print_freqs(\%report, "tiers", "Tier");
    print_freqs(\%report, "groups", "Group");
    print_freqs(\%report, "models", "Model");
    print_freqs(\%report, "last_transforms", "Last Transform");
}


# Main #
#
# NOTE: @key_rows and @score_rows are global mutable state shared by the sub-routines.
#
my ($channel, $city_id, @rest) = @ARGV;
my $num_records = $rest[0] + 0;
my $keys_file = format_file_name($channel, $city_id, "keys");
my $scores_file = format_file_name($channel, $city_id, "scores");

unless (-e $scores_file) {
    get_keys($channel, $city_id, $keys_file, $num_records);
}
get_scores($scores_file);
print_scoring_report($channel, $city_id);
