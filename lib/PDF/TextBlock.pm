package PDF::TextBlock;

use strict;
use warnings;
use Carp qw( croak );
use File::Temp qw(mktemp);
use Class::Accessor::Fast;
use PDF::TextBlock::Font;

use base qw( Class::Accessor::Fast );
__PACKAGE__->mk_accessors(qw( pdf page text fonts x y w h lead parspace align hang flindent fpindent indent ));

use constant mm => 25.4 / 72;
use constant in => 1 / 72;
use constant pt => 1;

my $debug = 0;

=head1 NAME

PDF::TextBlock - Easier creation of text blocks when using PDF::API2

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

TODO - See t/ for examples.

=head1 DESCRIPTION

Neither Rick Measham's excellent PDF::API2 tutorial nor PDF::FromHTML are able to cope with
wanting a single word (or words) bolded inside a text block. This module makes that task
trivial.

=head1 METHODS

=head2 new

=over

=item x

X position from the left of the document. Default is 20/mm.

=item y

Y position from the bottom of the document. Default is 238/mm.

=item w

Width of this text block. Default is 175/mm.

=item h

Height of this text block. Default is 220/mm.

=item lead

From Rick's tutorial. I don't know what this does.  :)  Default is 15/pt.

=item parspace

From Rick's tutorial. I don't know what this does.  :)  Default is 0/pt.

=item align

Alignment of words in the text block. Default is 'justify'. Legal values:

=over

=item justify

Spreads words out evenly in the text block so that each line ends in the same spot
on the right side of the text block. The last line in a paragraph (too short to fill
the entire line) will be set to 'left'.

=item fulljustify

Like justify, except that the last line is also spread across the page. The last
line can look very odd with very large gaps.

=item left

Aligns each line to the left.

=item right

Aligns each line to the right.

=back

=back

=head2 apply

The original version of this method was text_block(), which is � Rick Measham, 2004-2007. 
The latest version of text_block() can be found in the tutorial located at http://rick.measham.id.au/pdf-api2/
text_block() is released under the LGPL v2.1.

=cut

sub apply {
   my ($self, %args) = @_;

   my $pdf  = $self->pdf;
   unless (ref $pdf eq "PDF::API2") {
      croak "pdf attribute (a PDF::API2 object) required";
   }

   $self->_apply_defaults();

   my $text = $self->text;
   my $page = $self->page;

   # Build %content_texts. A hash of all PDF::API2::Content::Text objects,
   # one for each tag (<b> or <i> or whatever) in $text.
   my %content_texts;
   foreach my $tag (($text =~ /<([^\/].*?)>/g), "default") {
      next if ($content_texts{$tag});
      my $content_text = $page->text;      # PDF::API2::Content::Text obj
      my $font;
      if ($self->fonts && $self->fonts->{$tag}) {
         $debug && warn "using the specific font you set for <$tag>";
         $font = $self->fonts->{$tag};
      } elsif ($self->fonts && $self->fonts->{default}) {
         $debug && warn "using the default font you set for <$tag>";
         $font = $self->fonts->{default};
      } else {
         $debug && warn "using PDF::TextBlock::Font default font for <$tag> since you specified neither <$tag> nor a 'default'";
         $font = PDF::TextBlock::Font->new({ pdf => $pdf });
         $self->fonts->{$tag} = $font;
      }
      $font->apply_defaults;
      $content_text->font($font->font, $font->size);
      $content_text->fillcolor($font->fillcolor);
      $content_text->translate($self->x, $self->y);
      $content_texts{$tag} = $content_text;
   }

   my $content_text = $content_texts{default};

   if ($self->align eq "text_right") {
      # Special case... Single line of text that we don't paragraph out...
      #    ... why does this exist? TODO: why can't align 'right' do this? 
      #    t/20-demo.t doesn't work align 'right', but I don't know why.
      $content_text->text_right($text);
      return 1;
   }

   my ($endw, $ypos);

   # Get the text in paragraphs
   my @paragraphs = split( /\n/, $text );

   # calculate width of all words
   my $space_width = $content_text->advancewidth(' ');

   my @words = split( /\s+/, $text );

   # Build a hash of widths we refer back to later.
   my %width = ();
   foreach my $word (@words) {
      next if exists $width{$word};
      if (my ($tag) = ($word =~ /<(.*?)>/)) {
         my $stripped = $word;
         $stripped =~ s/<.*?>//g;
         if ($content_texts{$tag}) {
            $width{$word} = $content_texts{$tag}->advancewidth($stripped);
         } else {
            # Huh. They didn't declare this one, so we'll put default in here for them.
            $content_texts{$tag} = $content_texts{default};
            $width{$word} = $content_texts{$tag}->advancewidth($stripped);
         }
      } else {
         $width{$word} = $content_texts{default}->advancewidth($word);
      }
   }

   $ypos = $self->y;
   my @paragraph = split( / /, shift(@paragraphs) );

   my $first_line      = 1;
   my $first_paragraph = 1;

   # while we can add another line
   while ( $ypos >= $self->y - $self->h + $self->lead ) {

      unless (@paragraph) {
         last unless scalar @paragraphs;

         @paragraph = split( / /, shift(@paragraphs) );

         $ypos -= $self->parspace if $self->parspace;
         last unless $ypos >= $self->y - $self->h;

         $first_line      = 1;
         $first_paragraph = 0;
      }

      my $xpos = $self->x;

      # while there's room on the line, add another word
      my @line = ();

      my $line_width = 0;
      if ( $first_line && defined $self->hang ) {
         my $hang_width = $content_text->advancewidth( $self->hang );

         $content_text->translate( $xpos, $ypos );
         $content_text->text( $self->hang );

         $xpos       += $hang_width;
         $line_width += $hang_width;
         $self->indent($self->indent + $hang_width) if $first_paragraph;
      } elsif ( $first_line && defined $self->flindent ) {
         $xpos       += $self->flindent;
         $line_width += $self->flindent;
      } elsif ( $first_paragraph && defined $self->fpindent ) {
         $xpos       += $self->fpindent;
         $line_width += $self->fpindent;
      } elsif ( defined $self->indent ) {
         $xpos       += $self->indent;
         $line_width += $self->indent;
      }

      while ( 
         @paragraph and 
            $line_width + 
            ( scalar(@line) * $space_width ) +
            $width{ $paragraph[0] } 
            < $self->w
      ) {
         $line_width += $width{ $paragraph[0] };
         push( @line, shift(@paragraph) );
      }

      # calculate the space width
      my ( $wordspace, $align );
      if ( $self->align eq 'fulljustify'
         or ( $self->align eq 'justify' and @paragraph ) 
      ) {
         if ( scalar(@line) == 1 ) {
            @line = split( //, $line[0] );
         }
         $wordspace = ( $self->w - $line_width ) / ( scalar(@line) - 1 );
         $align = 'justify';
      } else {
         # We've run out of words to fill a full line
         $align = ( $self->align eq 'justify' ) ? 'left' : $self->align; 
         $wordspace = $space_width;
      }
      $line_width += $wordspace * ( scalar(@line) - 1 );

      my ($href, $tag);
      my $current_content_text = $content_texts{default};

      # If we want to justify this line, or if there are any markup tags
      # in here we'll have to split the line up word for word.
      if ( $align eq 'justify' or (grep /<.*>/, @line) ) {
         # TODO: [BUG1] This loop is DOA for align 'right' and 'center' with any tags. 
         foreach my $word (@line) {
            if (($tag) = ($word =~ /<(.*?)>/)) {
               # warn "tag is $tag";
               if ($tag =~ /^href/) {
                  ($href) = ($tag =~ /href="(.*?)"/);
                  # warn "href is now $href";
               } elsif ($tag !~ /\//) {
                  $current_content_text = $content_texts{$tag};
               }
            }
                
            my $stripped = $word;
            $stripped =~ s/<.*?>//g;
            $debug && _debug("$tag 1", $xpos, $ypos, $stripped);
            $current_content_text->translate( $xpos, $ypos );

            if ($href) {
               $current_content_text->text($stripped, -underline => [2,.5]);
               my $ann = $page->annotation;
               $ann->rect($xpos, $ypos - 3, $xpos + $width{$word} + $wordspace, $ypos + 10);
               $ann->url($href);
            } else {
               $current_content_text->text($stripped);
            }

            unless ($width{$word}) {
               warn "Can't find \$width{$word}";
            }
            $xpos += ( $width{$word} + $wordspace ) if (@line);

            if ($word =~ /\//) {
               if ($word =~ /\/href/) {
                  undef $href;
               } else {
                  $current_content_text = $content_texts{default};
               }
            }
         }
         $endw = $self->w;
      } else {
         # calculate the left hand position of the line
         if ( $align eq 'right' ) {
            $xpos += $self->w - $line_width;
         } elsif ( $align eq 'center' ) {
            $xpos += ( $self->w / 2 ) - ( $line_width / 2 );
         }
         # render the line
         $debug && _debug("default 2", $xpos, $ypos, @line);
         $content_text->translate( $xpos, $ypos );
         $endw = $content_texts{default}->text( join( ' ', @line ) );
      }
      $ypos -= $self->lead;
      $first_line = 0;
   }

   # Don't yet know why we'd want to return @paragraphs...
   # unshift( @paragraphs, join( ' ', @paragraph ) ) if scalar(@paragraph);
   return ( $endw, $ypos );  # , join( "\n", @paragraphs ) )
}


sub _debug{
   my ($msg, $xpos, $ypos, @line) = @_;
   printf("[%s|%d|%d] ", $msg, $xpos, $ypos);
   print join ' ', @line;
   print "\n";
}


=head2 garbledy_gook

Returns a scalar containing a paragraph of jibberish. Used by test scripts for 
demonstrations.

  my $jibberish = $tb->garbledy_gook(50);

The integer is the numer of jibberish words you want returned. Default is 100.

=cut

sub garbledy_gook {
   my ($self, $words) = @_;
   my $rval;
   $words ||= 100;
   for (1..$words) {
      for (1.. int(rand(10)) + 3) {
         $rval .= ('a'..'z')[ int(rand(26)) ];
      }
      $rval .= " ";
   }  
   chop $rval;
   return $rval;
}


# Applies defaults for you wherever you didn't explicitly set a different value.
sub _apply_defaults {
   my ($self) = @_;
   my %defaults = (
      x        => 20 / mm,
      y        => 238 / mm,
      w        => 175 / mm,
      h        => 220 / mm,
      lead     => 15 / pt,
      parspace => 0 / pt,
      align    => 'justify',
      fonts    => {},
   );
   foreach my $att (keys %defaults) {
      $self->$att($defaults{$att}) unless defined $self->$att;
   }

   # Create a new page inside our .pdf unless a page was provided.
   unless (defined $self->page) {
      $self->page($self->pdf->page);
   }

   # Use garbledy gook unless text was provided.
   unless (defined $self->text) {
      $self->text($self->garbledy_gook);
   }
}


=head1 AUTHOR

Jay Hannah, C<< <jay at jays.net> >>

=head1 BUGS

=over

=item align 'right' and 'center' with any markup tags is broken 

This software can't currently handle those alignments with any markup tags. 
As written the software is in a loop calculating x position of each word, 
one word at a time from left to right. But in the case of aligns 'right' 
and 'center' we don't know the position of the first word until we know the 
x positions of ALL words. 
We need a smarter handler for this scenario. See t/30-demo.t. [BUG1]

=back

Please report any bugs or feature requests to C<bug-pdf-textblock at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PDF-TextBlock>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PDF::TextBlock

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=PDF-TextBlock>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/PDF-TextBlock>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/PDF-TextBlock>

=item * Search CPAN

L<http://search.cpan.org/dist/PDF-TextBlock>

=item * Version control

L<http://github.com/jhannah/pdf-textblock/tree/master>

=back

=head1 ACKNOWLEDGEMENTS

This module started from, and has grown on top of, Rick Measham's (aka Woosta) 
"Using PDF::API2" tutorial: http://rick.measham.id.au/pdf-api2/

=head1 COPYRIGHT & LICENSE

Copyright 2009 Jay Hannah, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of PDF::TextBlock
