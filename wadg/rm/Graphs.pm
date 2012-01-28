############################################################
#
# Module: wadg::rm::Graphs
#
# Created: 20.April.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved.
# Based on subs from Report Magic (19.Feb.1999-20.Mar.2000)
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
# 20.APR.2000 REQUIRES GD::Graph 1.30 or later!!!         JW
############################################################
package wadg::rm::Graphs;
use strict;
use HTML::Entities;
use GD::Graph;					# Requires GD::Text::Align
use GD::Graph::Data;
use GD;							# For 1 pixel place holder
# ALSO Requires GDGraph3d for 3d graphs

BEGIN {
	use vars       qw($VERSION @ISA);

	$VERSION = do { my @r = (q$Revision: 2.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw();
} # end BEGIN
# non-exported package globals go here
use vars      qw( %_entity2char %_decompose_entity );

#
# These hashes are necessary for creating the text in 
# the graphs when using gdFonts because the character set 
# in them is not latin-1 (it's latin-2, incidentally)
#
my %_entity2char = (
 amp     => '&',  # ampersand 
'gt'     => '>',  # greater than
'lt'     => '<',  # less than
 quot    => '"',  # double quote
 Aacute  => 'Á',
 Acirc   => 'Â',
 Auml    => 'Ä',
 Ccedil	=> 'Ç',
 Eacute	=> 'É',
 Euml    => 'Ë',
 Iacute	=> 'Í',
 Icirc	=> 'Î',
 Oacute	=> 'Ó',
 Ocirc	=> 'Ô',
 Ouml	=> 'Ö',
 Uacute	=> 'Ú',
 Uuml	=> 'Ü',
 Yacute	=> 'Ý',
 aacute	=> 'á',
 acirc	=> 'â',
 auml	=> 'ä',
 ccedil	=> 'ç',
 eacute	=> 'é',
 euml	=> 'ë',
 iacute	=> 'í',
 icirc	=> 'î',
 oacute	=> 'ó',
 ocirc	=> 'ô',
 ouml	=> 'ö',
 szlig	=> 'ß',
 uacute	=> 'ú',
 uuml	=> 'ü',
 yacute	=> 'ý',
 copy   => '©',
 reg    => '®',
 nbsp   => ' ',
 curren => '¤',
 brvbar => '¦',
 sect   => '§',
 uml    => '¨',
 shy    => '­',
 deg    => '°',
 acute  => '´',
 cedil  => '²',
'times' => '×',    # times is a keyword in perl
 divide => '÷',
);
# Used to 'decompose' entities: ó => o'
my %_decompose_entity = (
 acute	=> "\'",
 circ	=> '^',
 cedil	=> '²',
 grave	=> '`',
 ring	=> '°',
 tilde	=> '~',
 uml	=> '¨',
 slash	=> '/',
);

############################
## The object constructor ##
############################
sub new {
	my $self = {};
	my $proto = shift;
	my %parms = @_;
	my $class = ref($proto) || $proto;

	# Defaults
	$self->{cycle_colors} = 1;
	$self->{shadows} = 1;
	# The old palette was [qw(lgreen lblue lred lpurple lyellow green blue red purple yellow)];
	$self->{palette} = ['#9999CC', '#CCCC66', '#339900', '#990000', '#FFCC33', '#996699', '#6699FF', '#0066CC', '#FF9900', '#666699'];
	$self->{format}  = 'png';
	$self->{floor} = 0;
	
	# Parse named parameters
	my($k, $v);
	local $_;
	while( ($k, $v) = each %parms ) {
		$self->{$k} = $v;
	} # end while 
	
	bless ($self, $class);
	return $self;
} # end new

##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: graph
#
# Args: $type
#	$type	The graph type specifier: pie,line,bar
#
# Description: Graphs the data in $self->{data} using the 
# specified graph type and settings installed.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999MAR10 Original sub created                          JW
# 2000APR20 Coverted to meth0d of wadg::rm::Graphs        JW
#           Reorganized,implemented GD::Graph 1.30 stuff
# 29Jul2002 Implemented number formatter for y labels     JW
# 10Mar2003 Added trucated text and elipsis to labels     JW
# ----------------------------------------------------------
sub graph {
	my $self = shift;

	my( $i, $graph );
	my $decode = \&_gd_Decode_HTML_Entities;
	if( defined $self->{graph_font} ) {
		### Build an object until Martien fixes 
		### can_do_ttf to a class method.
		my $g = new GD::Graph( 1, 1 );
		if( $g->can_do_ttf ) {
			$decode = \&HTML::Entities::decode;
		} # end if
	} # end if
	my @chart = @{$self->{data}};
	my $data = new GD::Graph::Data;
	my $column = $self->{column};
	my $x_label = &$decode( $self->{x_label} );
	my $y_label = &$decode( $self->{y_label} );
	my $chartFile = $self->{file};
	my $title = &$decode( $self->{title} );
	my $height = $self->{height};
	my $width = $self->{width};		# Minumum width, make it wider if more data.
		# [ JW] This is a kludge. In 2.0, let's use the GD::Graph::Data object 
		# and do some estimating based on max and mins. Also, GDGraph3d could try 
		# to better handle data that is wider than the width of the graph by either 
		# (a) dropping intermediate points or (b) allowing two plots on a given pixel.
	   if( (@chart + 100) > $width ) {
	   	$width = @chart + 100;
	   } # end if
	my( $type ) = @_;

	#
	# Adjust $column for chart type
	#
	if( $type =~ /pie/i ) {
		$column = lc($column);
	} elsif( $type =~ /bar/i ) {
		$column = uc($column);
	} elsif( $type =~ /line/i ) {
		$column = uc($column);
	} # endif

	#
	# Preprocess the data for the graph points 
	# [This is two loops because the second loop is dependent on first loop's results]
	#    Check floor and store non-matching values in @others
	#    Set options for making readable labels (note only check labels that show)
	#
	my @others;
	for $i ( 0..@chart ) {
		next unless defined $chart[$i]{$column};
		if( (($self->{floor} > 0) && ($chart[$i]{$column} < $self->{floor})) ||
		    (($self->{floor} < 0) && ($i > -$self->{floor}))
		  ) {
			push @others, $i;
		} elsif( defined $chart[$i]{'name'} && length( $chart[$i]{'name'} ) > 20 ) {
			$chart[$i]{name} = $chart[$i]{number} . '. ' . substr( $chart[$i]{name}, 0, 20 ) . $self->{ellipsis}
		} # end if
	} # end for
	
	#
	# Put the data into the GD::Graph::Data structure
	#    Ignore undefined values.
	#    Convert all text to the proper character set
	#    If @others is > 1 then put those points into an 'other' point
	#
	my $other = 0;
	for $i ( 0 .. @chart ) {
		if( defined $chart[$i]{$column} ) {
			if( (@others > 1) && grep {$_== $i} @others ) {
				$other += $chart[$i]{$column};
			} else {
				$data->add_point( &$decode( $chart[$i]{name} ), $chart[$i]{$column} );
			} # end if
		} # end if
	} # end for
	# Make the 'other' point, if it exists
	if( $other ) {
		$data->add_point( $self->{other_label}, $other );
	} # end if

	# - Adjust maximum scale. GD::Graph doesn't seem to do it well.
	# *** This is something Martien and I are working on fixing in the GD::Graph modules [ JW]***
	# - Just round up two significant digits
	my $maxY;
	(undef, $maxY) = $data->get_min_max_y( 1 );
	if( defined $maxY ) {
		my $factor = 10 ** (length( $maxY ) - 2);
		$maxY = int( $maxY / $factor ) + 1;
		$maxY *= $factor;
	} # end if

	# - Set color or default to black on white
	my $textColor = 'black';
	my $bgColor = 'white';
	if( defined $self->{font_color} ) {
		$textColor = $self->{font_color};
	} # end if
	if( defined $self->{bg_color} ) {
		$bgColor = $self->{bg_color};
	} # end if

	
	
	
	if( $type =~ /pie/i ) {
		#
		# Pie Chart
		#
		if( $self->{'3d'} && $type !~ /pie2d/ ) {
			use GD::Graph::pie3d;
			$graph = new GD::Graph::pie3d( $width, $height );
		} else {
			use GD::Graph::pie;
			$graph = new GD::Graph::pie( $width, $height );
			$graph->set( '3d' => 0 );
		} # end if

		$graph->set	(
			title		   =>	$title,
			transparent => 1,
		);
		$graph->set_text_clr	( $textColor );

		# -- Keep label color black because it's on top of the pie slices
		$graph->set( axislabelclr => 'black' );

		$graph->set( bgclr => $bgColor );
		$graph->set( fgclr => $textColor );
		$graph->set( dclrs => $self->{palette} );
		if( (defined $self->{graph_font}) && ($graph->can_do_ttf) ) {
			my( $fnt, @sizes ) = split( /\s*,\s*/, $self->{graph_font} );
			$graph->set_title_font( $fnt, $sizes[0] || 16 );
			$graph->set_label_font( $fnt, $sizes[1] || 11 );
			$graph->set_value_font( $fnt, $sizes[2] || 9 );
		} else {
			$graph->set_title_font( GD::gdLargeFont );
			$graph->set_label_font( GD::gdMediumBoldFont );
			$graph->set_value_font( GD::gdMediumBoldFont );
		} # end if
	
	
	
	} elsif( $type =~ /bar/i ) {
		#
		# Bar chart
		#
		my $use_box = 1; 	# To get fill color on 2d graphs
		if( $self->{'3d'} && $type !~ /bars?2d/ ) {
			use GD::Graph::bars3d;
			$graph = new GD::Graph::bars3d( $width, $height );
			$use_box = 0; 	# On 3d only do back box, not front
		} else {
			use GD::Graph::bars;
			$graph = new GD::Graph::bars( $width, $height );
		} # end if
		$graph->set	(
			transparent => 1,
			y_label	=>	$y_label,
			x_label	=>	$x_label,
			title		=>	$title,
			long_ticks	=>	1,
			x_ticks	=>	1,
			x_label_position	=>	.5,
			y_label_position	=>	.5,
			x_labels_vertical	=>	1,
			axis_space	=>	3,
			bar_spacing => 7,
			y_number_format => $self->{formatter} || '%d',
			cycle_clrs => $self->{cycle_colors},
			b_margin => 3,
			x_all_ticks => 1,
			box_axis => $use_box,
		);

		$graph->set( shadow_depth => 4, shadowclr => $textColor ) if $self->{shadows};
		
		# - Set colors and fonts
		$graph->set_text_clr	( $textColor );
		$graph->set( bgclr => $bgColor );

		# Make a foreground color that is between the text and background so it blends in
		my( $r, $g, $b ) = GD::Graph::colour::_rgb( $textColor );
		my( $r1, $g1, $b1 ) = GD::Graph::colour::_rgb( $bgColor );
		$r = int( ($r + $r1) / 2 );
		$g = int( ($g + $g1) / 2 );
		$b = int( ($b + $b1) / 2 );
		my $fgclr = GD::Graph::colour::rgb2hex( $r, $g, $b );
		$graph->set( fgclr => $fgclr	);

		$graph->set( dclrs => $self->{palette} );
		$graph->set( boxclr => $self->{graph_color} ) if defined $self->{graph_color};
		
		if( (defined $self->{graph_font}) && ($graph->can_do_ttf) ) {
			my( $fnt, @sizes ) = split( /\s*,\s*/, $self->{graph_font} );
			$graph->set_title_font( $fnt, $sizes[0] || 16 );
			$graph->set_x_label_font( $fnt, $sizes[1] || 11 );
			$graph->set_x_axis_font( $fnt, $sizes[2] || 9 );
			$graph->set_y_label_font( $fnt, $sizes[1] || 11 );
			$graph->set_y_axis_font( $fnt, $sizes[2] || 9 );
		} else {
			$graph->set_title_font( GD::gdLargeFont );
			$graph->set_x_label_font( GD::gdMediumBoldFont );
			$graph->set_x_axis_font( GD::gdSmallFont );
			$graph->set_y_label_font( GD::gdMediumBoldFont );
			$graph->set_y_axis_font( GD::gdSmallFont );
		} # end if

		my $lblSkip = int( @chart / 12 );
		if( $lblSkip > 1 ) {
			$graph->set( x_label_skip => $lblSkip );
		} # end if

		if( defined $maxY ) {
			$graph->set( y_max_value => $maxY );
		} # end if
		$graph->set( y_min_value => 0 );

	} elsif( $type =~ /line/i ) {
		#
		# Line chart
		#
		my $use_box = 1; 	# To get fill color on 2d graphs
		if( $self->{'3d'} && $type !~ /lines?2d/ ) {
			use GD::Graph::lines3d;
			$graph = new GD::Graph::lines3d( $width, $height );
			$use_box = 0;		# On 3d only do back box, not front
		} else {
			use GD::Graph::lines;
			$graph = new GD::Graph::lines( $width, $height );
		} # end if
		$graph->set	(
			transparent => 1,
			y_label	=>	$y_label,
			x_label	=>	$x_label,
			title		=>	$title,
			long_ticks	=>	1,
			x_ticks	=>	1,
			x_label_position	=>	.5,
			y_label_position	=>	.5,
			x_labels_vertical	=>	1,
			y_number_format => $self->{formatter} || '%d',
			axis_space	=>	3,
			line_width	=>	8,
			b_margin => 3,
			box_axis => $use_box,
		);

		# - Set colors and fonts
		$graph->set_text_clr	( $textColor );
		$graph->set( bgclr => $bgColor );

		# Make a foreground color that is between the text and background so it blends in
		my( $r, $g, $b ) = GD::Graph::colour::_rgb( $textColor );
		my( $r1, $g1, $b1 ) = GD::Graph::colour::_rgb( $bgColor );
		$r = int( ($r + $r1) / 2 );
		$g = int( ($g + $g1) / 2 );
		$b = int( ($b + $b1) / 2 );
		my $fgclr = GD::Graph::colour::rgb2hex( $r, $g, $b );
		$graph->set( fgclr => $fgclr	);

		$graph->set( dclrs => $self->{palette} );
		$graph->set( boxclr => $self->{graph_color} ) if defined $self->{graph_color};

		if( (defined $self->{graph_font}) && ($graph->can_do_ttf) ) {
			my( $fnt, @sizes ) = split( /\s*,\s*/, $self->{graph_font} );
			$graph->set_title_font( $fnt, $sizes[0] || 16 );
			$graph->set_x_label_font( $fnt, $sizes[1] || 11 );
			$graph->set_x_axis_font( $fnt, $sizes[2] || 9 );
			$graph->set_y_label_font( $fnt, $sizes[1] || 11 );
			$graph->set_y_axis_font( $fnt, $sizes[2] || 9 );
		} else {
			$graph->set_title_font( GD::gdLargeFont );
			$graph->set_x_label_font( GD::gdMediumBoldFont );
			$graph->set_x_axis_font( GD::gdSmallFont );
			$graph->set_y_label_font( GD::gdMediumBoldFont );
			$graph->set_y_axis_font( GD::gdSmallFont );
		} # end if


		my $lblSkip = int( @chart / 12 );
		if( $lblSkip > 1 ) {
			$graph->set( x_label_skip => $lblSkip );
		} # end if

		if( defined $maxY ) {
			$graph->set( y_max_value => $maxY );
		} # end if
		$graph->set( y_min_value => 0 );

	} # end if
	
	
	#
	# Now that we've set all the options, plot a graph
	#
	my $gd = $graph->plot( $data );


	#
	# And write the file
	#
	undef $!;
	if( open( GRAPH, ">$self->{filename}" ) ) {
		# Use binary files on Windows
		binmode( GRAPH );
		
		# If the graph failed to build, then replace it with a 1 pixel place holder
		# It can fail if all data is '0' and it's a pie chart for instance
		unless( defined $gd ) {
			$gd = new GD::Image( 1, 1 );
			$gd->transparent( $gd->colorAllocate(255,255,255) );
		} # end if

		# Now write to file in the proper format
		if( lc($self->{format}) eq 'png' ) {
			print GRAPH $gd->png;
		} elsif( lc($self->{format}) eq 'gif' ) {
			print GRAPH $gd->gif;
		} elsif( lc($self->{format}) eq 'jpeg' ) {
			print GRAPH $gd->jpeg;
		} # end if
		close( GRAPH );
	
	} else {
		warn "ERROR: Failed to write $self->{filename}. $!\n";
	} # end if

} # end graph


##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: _gd_Decode_HTML_Entities
#
# Args: @strings
#	@strings	An array of HTML-encoded strings to decode
#
# Description:
# A helper function to decode recognized HTML entities into 
# the character set used in the GD fonts. For entities not in 
# the font attempts to decompose them into character pairs.
# *NOTE* This is 'borrowed' (except the decompose)
# * straight out of Gisele Aas's HTML::Entities
# * module, then adjusted for the GD fonts
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _gd_Decode_HTML_Entities {
	my $array = [@_];
	my $c;
	for( @$array ) {
		s/&(\w)(\w*);?/$_entity2char{"$1$2"} || "$1$_decompose_entity{$2}" || "$1$2"/eg;
		s/&#(\d+);?/chr($1)/eg;
	} # end for

	return wantarray ? @$array : $array->[0];
} # end _gd_Decode_HTML_Entities


# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
