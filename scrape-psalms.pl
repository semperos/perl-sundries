use strict;
use warnings;
use 5.12.0;
use utf8;
use open IO => ':utf8';

use File::Copy qw(move); #move("/dev1/fileA","/dev2/fileB");
use File::Temp qw(tempfile);
require WWW::Mechanize;
require Mojo::DOM;

# Initialize reusable objects for HTTP requests
# and DOM parsing.
my $mech = WWW::Mechanize->new();
my $dom = Mojo::DOM->new();

# URL with form to request each Kathisma by number.
# Happens to have Kathisma I on it by default.
my $kathismata_url = "http://orthodox.seasidehosting.st/seaside/single_kathisma";

# File to write output to
my ( $fh, $file_name ) = tempfile();

# Fetch main Kathisma page
$mech->get( $kathismata_url );

open($fh, ">>", $file_name)
    or die "cannot open temp file for appending";

sub output_kathisma{
    $dom->parse($mech->content());
    my @kath_sections = $dom->find('h1, h2, h3, h4, p.dropCap')->each;
    output_sections($fh, \@kath_sections);
}

output_kathisma();

# Page elements
my %button = (
    value => "Go to Kathisma"
);
# Now rest of Kathismata
foreach my $num ( 2 .. 20 ) {
    print "Submitting form for Kathisma $num...\n";
    my %fields = (
        # Don't know Seaside can't do smth nicer,
        # but the field is named '12'
        12 => $num
    );
    $mech->submit_form(form_number => 1, fields => \%fields);
    print "URL is now: " . $mech->uri();
    print "Outputting Kathisma $num...\n";
    output_kathisma();
}

$fh->close;

# Move tmp file into place once done
move($file_name, "psalter.txt");

#############
# Real Work #
#############

# h1 - Kathisma #
# h2 - Psalm #
# h3 - Subtitle to previous h2
# h4 - Stasis marker (at end of each stasis)
sub output_sections{
    my $handle = shift;
    my @sections = @{shift()};

    print "Number of sections is " . @sections . "\n";

    # Keep track of Kathisma, Stasis, and Psalm,
    # each Psalm's text to be stored as:
    # |20|1|143|Blessed is the Lord my God...
    my $kathisma = 42; # bad value
    my $stasis = 1; # 1-3
    my $psalm = 420; # bad value
    foreach my $i ( 0 .. $#sections ) {
        my $h = $sections[$i];
        my $type = $h->type;
        my $text = $h->text;
        chomp($text);
        if ($type eq "h1" &&
                $text =~ /^Kathisma\s+(\d{1,2})/) {
            $kathisma = $1 + 0;
        } elsif ($type eq "h4"
                     && $text =~ /^Stasis/) {
            $stasis++;
        } elsif ($type eq "h2"
                     && $text =~ /^Psalm\s+(\d{1,3})/) {
            $psalm = $1 + 0;
        }

        # Print to file handle
        if ($type eq "p") {
            my $output = join("|", $kathisma, $stasis, $psalm, $text);
            print $handle $output . "\n";
        }
    }
}
