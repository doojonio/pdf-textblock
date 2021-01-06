BEGIN {
  my $rc;
  $rc = eval {
    require PDF::Builder;
    1;
  };
  if (!defined $rc) { $rc = 0; }
  unless($rc) {
    print qq{1..0 # SKIP these tests; PDF::Builder is not installed\n};
    exit;
  }
}

use Test::More tests => 19;

# Bold every other word under various alignments.

use PDF::Builder;
use PDF::TextBlock;

use constant mm => 25.4 / 72;
use constant in => 1 / 72;
use constant pt => 1;


ok(my $pdf = PDF::Builder->new( -file => "31-demo.pdf" ),   "PDF::Builder->new()");
my $fonts = { 
   b => PDF::TextBlock::Font->new({
      pdf  => $pdf,
      font => $pdf->corefont( 'Helvetica-Bold',    -encoding => 'latin1' ),
   }),
};


my ($endw, $ypos);
ok(my $tb  = PDF::TextBlock->new({
   pdf       => $pdf,
   y         => 270/mm,
   fonts     => $fonts,
   text      => "align => 'justify'",
}),                                                   "new()");
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

# Tag every other word with <b>.
my $text = $tb->garbledy_gook(30) . ".";
my $text_with_bold = $text;
$text_with_bold =~ s/(\w+) (\w+)/$1 <b>$2<\/b>/g;

$tb->y($ypos);
$tb->text($text);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text_with_bold);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

# ---
red_line($ypos);

$tb->y($ypos);
$tb->align('right');
$tb->text("align => 'right'");
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text_with_bold);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

# ---
red_line($ypos);

$tb->y($ypos);
$tb->align('center');
$tb->text("align => 'center'");
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text_with_bold);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

# ---
red_line($ypos);

$tb->y($ypos);
$tb->align('left');
$tb->text("align => 'left'");
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text_with_bold);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

# ---
red_line($ypos);

$tb->y($ypos);
$tb->align('fulljustify');
$tb->text("align => 'fulljustify'");
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

$tb->y($ypos);
$tb->text($text_with_bold);
ok(($endw, $ypos) = $tb->apply(),                     "apply()");

# ---
red_line($ypos);

$tb->y($ypos);
$tb->align('left');
$tb->text("Generated by t/31-demo.t");
$tb->fonts->{default}->fillcolor('darkblue');
ok(($endw, $ypos) = $tb->apply(),                     "apply()");



$pdf->save;    # Doesn't return true, even when it succeeds. -sigh-
$pdf->end;     # Doesn't return true, even when it succeeds. -sigh-
ok(-r "31-demo.pdf",                                  "31-demo.pdf created");

diag( "Testing PDF::TextBlock $PDF::TextBlock::VERSION, Perl $], $^X" );


sub red_line {
   my ($ypos) = @_;
   my $red_line = $tb->page->gfx;
   $red_line->strokecolor('red');
   $red_line->move( 20/mm, $ypos + 4/mm );
   $red_line->line( 195/mm, $ypos + 4/mm );
   $red_line->stroke;
}


