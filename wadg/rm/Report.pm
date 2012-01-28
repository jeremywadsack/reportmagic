############################################################
#
# Module: wadg::rm::Report
#
# Created: 20.March.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved.
# Based on subs from Report Magic (19.Feb.1999-20.Mar.2000)
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
# 2000.May.29 Converted entire class to HTMLWriter output JW
# 2000.Oct.17 Changed all &nbsp; to &#160; for XHTML      JW
############################################################
package wadg::rm::Report;
use strict;
use HTML::Entities;
use File::Basename;
use wadg::rm::Graphs;
use wadg::Errors;
use wadg::HTMLWriter;

BEGIN {
	use vars       qw($VERSION @ISA);

	$VERSION = do { my @r = (q$Revision: 2.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw();
} # end BEGIN
# non-exported package globals go here
use vars      qw( $CONFIG $GLOBALS $LANG $FORMATTER );

############################
## The object constructor ##
############################
# ----------------------------------------------------------
# Options:
#	token	A code representing the report (e.g. 'x', 'm', 'W', etc.)
#	handle	A file handle reference for writing to
#	columns	The current list of columns for the current data 
#           (This value may be changes between _table_row calls)
#
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000APR25 Moved all init stuff to initialize            JW
# ----------------------------------------------------------
sub new {
	my $self = {};
	my $proto = shift;
	my %parms = @_;
	my $class = ref($proto) || $proto;

	bless ($self, $class);
	$self->_initialize( %parms ) or return;

	#** carp unless defined _LANG, _CDATA, _CONFIG, and _FORMATTER
	return $self;
} # end new





##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################

# ----------------------------------------------------------
# Sub: process
#
# Args: @data
#	@data	The data columns in the report line
#
# Description: Processes a report line for the report.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb24 Modified to read all text from data file      JW
# 1999Mar09 Adjusted to parse all available columns
#           Incorporated Simple1 & Simple2 as settings    JW
# 2000Apr25 Removed all formatting to format_data_label
#           called in _table_row (w/ format_graph_label)  JW
# ----------------------------------------------------------
sub process {
	my $self = shift;
	my( $point, @myLine ) = $self->_format_data_columns( @_ );

	# Swap shaded rows
	$self->{_shaded_row} = 1 - $self->{_shaded_row};
	
	# Summarize the line
	$self->_summarize( $point, @myLine );

	# Output the table row
	$self->_data_row( $point, @myLine );
} # end process



# ----------------------------------------------------------
# Sub: title
#
# Args: (None)
#
# Description: Write out the title of the reports
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb19 Modified to support multi-file reports        JW
# 1999Feb24 Modified to read all text from data file      JW
# 10Mar2003 Added 'width' attr's to bounding table        JW
# ----------------------------------------------------------
sub title {
	my $self = shift;
	my $title = $self->{_CONFIG}{$self->{token}}{LongName};
	my( $link ) = split /[\012\015]+/, $self->{_CONFIG}{$self->{token}}{ShortName};

	# Start with a comment to help separate reports when in a single file
	$self->{writer}->write( $self->{writer}->comment( <<END
	
  ================================================================
  ========================   $title   ====================
  ================================================================
  
END
	) );
	
	#
	# Create bounding table if in non-frames mode.
	#
	if( defined $self->{_CONFIG}{reports}{Navigation_Content} ) {
		my %td = ( align => 'left', valign => 'top' );
		$td{background} = $self->{_CONFIG}{reports}{Navigation_Background} if defined $self->{_CONFIG}{reports}{Navigation_Background};
		$td{bgcolor} = $self->{_CONFIG}{reports}{Navigation_BG_Color} if defined $self->{_CONFIG}{reports}{Navigation_BG_Color};
		if( $self->{_CONFIG}{reports}{Navigation_Position} eq 'LEFT' ) {
			$td{width} = '22%';
			$self->{writer}->write( 
				$self->{writer}->start_table( {border => 0, cellspacing => 0, cellpadding => 7, width => '100%'} ),
				$self->{writer}->start_tr(),
				$self->{writer}->td( \%td, $self->{_CONFIG}{reports}{Navigation_Content} ),
				$self->{writer}->start_td( {align => 'left', valign => 'top', width => '78%'} ),
			);
		} elsif( $self->{_CONFIG}{reports}{Navigation_Position} eq 'TOP' ) {
			$td{align} = 'CENTER';
			$self->{writer}->write( 
				$self->{writer}->start_table( {border => 0, cellspacing => 0, cellpadding => 7, width => '100%'} ),
				$self->{writer}->tr(	$self->{writer}->td( \%td, $self->{_CONFIG}{reports}{Navigation_Content} ) ),
				$self->{writer}->start_tr(),
				$self->{writer}->start_td( {align => 'left', valign => 'top'} ),
			);
		} elsif( $self->{_CONFIG}{reports}{Navigation_Position} eq 'RIGHT' ) {
			$self->{writer}->write( 
				$self->{writer}->start_table( {border => 0, cellspacing => 0, cellpadding => 7, width => '100%'} ),
				$self->{writer}->start_tr(),
				$self->{writer}->start_td( {align => 'left', valign => 'top', width => '78%'} ),
			);
		} else {
			$self->{writer}->write( 
				$self->{writer}->start_table( {border => 0, cellspacing => 0, cellpadding => 7, width => '100%'} ),
				$self->{writer}->start_tr(),
				$self->{writer}->start_td( {align => 'left', valign => 'top'} ),
			);
		} # end if
	} # end if

	#
	# Write out the name of the report
	#
	$self->{writer}->write( 
		$self->{writer}->a( {name => $link}, '&#160;' ),
		$self->{writer}->h2( "&#160;&#160;$title&#160;&#160;" ),
	);

} # end title



# ----------------------------------------------------------
# Sub: start_table
#
# Args: (None)
#
# Description: Draws the table headers for the current column
# specification. Does not draw tables for filter rows.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb24 Support any report style and all columns      JW
# 2000May06 Removed GeneralSummary specifics to subclass  JW
# 31May2001 Added handler to ignore '*' columns           JW
# ----------------------------------------------------------
sub start_table {
	my $self = shift;
	my @columns = split(/ */, $self->{columns});
	my $altString = '';

	# If these are special columns, then don't do headers (or table)
	return if $columns[0] eq '*';
	
	# - Create the table and headers
	my $cName = '';
	my $columnTypes = ':';
	foreach (@columns) {
		$_ .= '_' if $_ eq uc;

		my $columnType = $self->{_CDATA}->val( $_, 'Type' ) || '';
		$columnType = 'Data' if $columnType eq '';
		$columnTypes .= "$columnType:";
	} # end foreach

	#
	# Filters don't use tables, so just return
	#
	return 0 if $columnTypes =~ /:filter:/i;
	
	#
	# Insert graphs image tags for active column
	#
	#my $width = 400;			# Can't do this right now 'cause width is dynamically set to fit data
	#my $height = 300;
	my $column = substr( $self->{_CONFIG}{$self->{token}}{Active_Column}, 0, 1 );

	# Get the file name and the URL path part (if defined)
	my @names = $self->_get_graph_filenames();
	my $path = $self->{_CONFIG}{graphs}{URL_To} || '';

	foreach ( @names ) {
		my $altString = '';
		if( /_(pie)\.[^\.]+$/ ) {
			$altString = $self->{_FORMATTER}->formatMessage( $self->{_LANG}->val( 'Text', 'O0007' ), 
			                                                 $self->{_CONFIG}{$self->{token}}{LongName}, 
			                                                 $self->{_CDATA}->val( lc($column), 'LongName' ), 
			                                                 $self->{_CONFIG}{$self->{token}}{DataName} );
		} else {
			$altString = $self->{_FORMATTER}->formatMessage( $self->{_LANG}->val( 'Text', 'O0007' ), 
			                                                 $self->{_CONFIG}{$self->{token}}{LongName}, 
			                                                 $self->{_CDATA}->val( uc($column) . '_', 'LongName' ), 
			                                                 $self->{_CONFIG}{$self->{token}}{DataName} );
		} # end if
		$self->{writer}->write( 
			$self->{writer}->p( {align => 'CENTER'}, $self->{writer}->br(),
				$self->{writer}->img( {src => $path . $_, alt => $altString} )
			)
		);
	} # end if

	#
	# Has some data columns so do it normally
	#
	my $tableHeaders = $self->{writer}->start_tr();
	$tableHeaders .= $self->{writer}->th( {colspan => 2, scope => 'COL'}, $self->{_CONFIG}{$self->{token}}{DataName} );
	foreach $column (@columns) {
		next if lc($self->{_CDATA}->val( $column, 'Type' )) eq 'level';
		next if lc($self->{_CDATA}->val( $column, 'Type' )) eq 'index';
		# - Get the LongName for the column
		$cName = $self->{_CDATA}->val( $column, 'LongName' );
		if( $cName eq '' ) {
			# Unknown header type
			wadg::Errors::warning( 'W0002', $column );
			next;
		} # end if 
		$tableHeaders .= $self->{writer}->th( {scope => 'COL'}, $cName );
	} # end foreach
	$tableHeaders .= $self->{writer}->end_tr();

	# - Create some summary text for the table
	#   Remove any HTML tags, though
	$altString = $self->{_CONFIG}{$self->{token}}{Description};
	$altString =~ s/<.+?>//g;
	my $tableBorder = '1';

	$self->{writer}->write( 
		$self->{writer}->br(),
		$self->{writer}->start_div( {align => 'CENTER'} ),
		$self->{writer}->start_table( {cellpadding => 5, cellspacing => 0, border => $tableBorder, width => '85%', summary => $altString } ),
		$tableHeaders,
	);
	
	return 0;
} # end start_table



# ----------------------------------------------------------
# Sub: end_report
#
# Args: (None)
#
# Description: Calls the report specific summary, and 
# closes the Navigation table, if any.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb19 Created to function                           JW
# 1999Feb24 Added table around the summary information    JW
# 1999Mar08 Changed name to endReport.                    JW
# 2000May06 Changed to end_report; removed graphing stuff JW
# 31May2001 Added support for report span date message    JW
# 10Mar2003 Added 'width' attr to bounding table cells    JW
# ----------------------------------------------------------
sub end_report {
	my $self = shift;

	return if $self->{token} eq '';

	#
	# Do report specific summaries and close table.
	#
	$self->_write_summary();

	#
	# If Analog's REPORTSPAN was used, then output range
	#
	if( defined $self->{REPORTSPAN} ) {
		$self->{writer}->write( 
			$self->{writer}->p( {class => 'fineprint'},
				# Globals are never imported into the object, so get them from the class
				$self->{_FORMATTER}->formatMessage( $self->{_LANG}->val( 'Text', 'O0004' ), $$GLOBALS{'DataStart'}, $$GLOBALS{'DataEnd'} ),
			)
		);
	} # end if
	
	#
	# Close bounding table if in non-frames mode.
	#
	if( defined $self->{_CONFIG}{reports}{Navigation_Content} ) {
		my %td = ( align => 'left', valign => 'top' );
		$td{background} = $self->{_CONFIG}{reports}{Navigation_Background} if defined $self->{_CONFIG}{reports}{Navigation_Background};
		$td{bgcolor} = $self->{_CONFIG}{reports}{Navigation_BG_Color} if defined $self->{_CONFIG}{reports}{Navigation_BG_Color};
		if( $self->{_CONFIG}{reports}{Navigation_Position} eq 'RIGHT' ) {
			$td{width} = '22%';
			$self->{writer}->write( 
				$self->{writer}->end_td(),
				$self->{writer}->td( \%td, $self->{_CONFIG}{reports}{Navigation_Content} ),
				$self->{writer}->end_tr(),
				$self->{writer}->end_table(),
			);
		} elsif( $self->{_CONFIG}{reports}{Navigation_Position} eq 'BOTTOM' ) {
			$td{align} = 'center';
			$td{valign} = 'bottom';
			$self->{writer}->write( 
				$self->{writer}->end_td(),
				$self->{writer}->end_tr(),
				$self->{writer}->tr(	$self->{writer}->td( \%td, $self->{_CONFIG}{reports}{Navigation_Content} ) ),
				$self->{writer}->end_table(),
			);
		} else {
			$self->{writer}->write( 
				$self->{writer}->end_td(),
				$self->{writer}->end_tr(),
				$self->{writer}->end_table(),
			);
		} # end if
	} # end if

} # end end_report



# ----------------------------------------------------------
# Sub: end_table
#
# Args: (None)
#
# Description: Closes the table for data columns.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999May15 Encapsulated to end the data table.           JW
# 2000May06 Removed tables from filter rows               JW
# 2000Jun28 Fixed bug when columns are undefined          JW
# 29Jul2002 Added number formatting sub for graphs        JW
# ----------------------------------------------------------
sub end_table {
	my $self = shift;

	#
	# Filters don't use tables, don't have graphs, 
	# so just return if there are any
	#
	return if substr( $self->{columns}, 0 , 1 ) eq '*';
	foreach (split(/ */, $self->{columns})) {
		$_ .= '_' if $_ eq uc;
		my $type = $self->{_CDATA}->val( $_, 'Type' );
		return if defined($type) && ($type =~ /filter/i);
	} # end foreach

	$self->{writer}->write( 
		$self->{writer}->end_table(),
		$self->{writer}->end_div(),
	);
	
	#
	# Make graphs for active column(s)
	#
	my %opts = ( 
		data         => $self->{_chart},
		x_label      => $self->{_CONFIG}{$self->{token}}{DataName},
		title        => $self->{_CONFIG}{$self->{token}}{LongName},
		width        => $self->{_CONFIG}{$self->{token}}{Width} ||
		                $self->{_CONFIG}{graphs}{Width} || 400,
		height       => $self->{_CONFIG}{$self->{token}}{Height} ||
		                $self->{_CONFIG}{graphs}{Height} || 300,
		graph_font   => $self->{_CONFIG}{graphs}{Font},
		font_color   => $self->{_CONFIG}{graphs}{Font_Color} || $self->{_CONFIG}{$self->{token}}{Font_Color},
		bg_color     => $self->{_CONFIG}{$self->{token}}{BG_Color},
		graph_color  => $self->{_CONFIG}{graphs}{BG_Color} || $self->{_CONFIG}{$self->{token}}{BG_Color},
		avg_color    => $self->{_CONFIG}{graphs}{Average_Line_Color},
		other_label  => $self->{_LANG}->val( 'Text', 'O0013' ),
		ellipsis     => $self->{_LANG}->val( 'Symbols', 'ellipsis' ),
		cycle_colors => 1,
		shadows      => 1,
		'3d'         => 1,
	);
	$opts{palette}      = [split /\s*,\s*/, $self->{_CONFIG}{graphs}{Palette}] if defined $self->{_CONFIG}{graphs}{Palette};
	$opts{cycle_colors} = $self->{_CONFIG}{graphs}{Cycle_Colors} if defined $self->{_CONFIG}{graphs}{Cycle_Colors};
	$opts{shadows}      = $self->{_CONFIG}{graphs}{Drop_Shadows} if defined $self->{_CONFIG}{graphs}{Shadows};
	$opts{'3d'}         = $self->{_CONFIG}{graphs}{'3d'} if defined $self->{_CONFIG}{graphs}{'3d'};
	$opts{'3d'}         = $self->{_CONFIG}{$self->{token}}{'3d'} if defined $self->{_CONFIG}{$self->{token}}{'3d'};
#	$opts{avg}          = $self->{_summaries}{$dType}{total}{$self->{_CONFIG}{$self->{token}}{Active_Column}} / $self->{_summaries}{$dType}{count} if $self->{_summaries}{$dType}{count};

	# Clean up graphs_Font 
	# -- if imported from [reports] then remove it
	delete $opts{graph_font} if defined $opts{graph_font} && ($opts{graph_font} eq $self->{_CONFIG}{reports}{Font});
	
	#
	# If the Path_To setting is given, then use that as the location to 
	# write images. If not, then use the same folder as the reports
	#
	## NOTE: This makes Path_To releative to the working directory
	## To make it relative to ouput directory, read that first, then catdir( out, path );
	#
	# - Use fileparse() to get $outDir, 'cause dirname() will make 
	#   'reports/' into './' and we want 'reports/'
	my $outDir = $self->{_CONFIG}{graphs}{Path_To};
	unless( defined $outDir ) {
		( undef, $outDir, undef ) = fileparse( $self->{_CONFIG}{$self->{token}}{File_Out} );
	} # end unless

	foreach ( $self->_get_graph_filenames() ) {
		my $type = $1 if /_([^\.]+)\.[^\.]+$/;
		$opts{format} = $1 if /\.([^\.]+)$/;
		$opts{filename} = File::Spec->catfile( $outDir, $_ );
		if( $type =~ /pie/i ) {
			$opts{column} = lc(substr( $self->{_CONFIG}{$self->{token}}{Active_Column}, 0, 1));
			$opts{y_label}  = $self->{_CDATA}->val( $opts{column}, 'LongName' );
			$opts{floor} = 3;
			$opts{formatter} = sub{ $self->_format_data_item( $_[0], $opts{column} ) };
		} elsif( $type =~ /bar/i ) {
			$opts{column} = uc(substr( $self->{_CONFIG}{$self->{token}}{Active_Column}, 0, 1));
			$opts{'y_label'}  = $self->{_CDATA}->val( $opts{column} . '_', 'LongName' );
			$opts{floor} = int((100 - $opts{width})/11);
			$opts{formatter} = sub{ $_ = $self->_format_data_item( $_[0], $opts{column} . '_' ); s/<[^>]+>//g; $_ };
		} else {
			$opts{column} = uc(substr( $self->{_CONFIG}{$self->{token}}{Active_Column}, 0, 1));
			$opts{'y_label'}  = $self->{_CDATA}->val( $opts{column} . '_', 'LongName' );
			$opts{floor} = 0;
			$opts{formatter} = sub{ $self->_format_data_item( $_[0], $opts{column} . '_' ) };
		} # end if

		# Doing this leads to broken links, since the <img> doesn't know if data is there yet
		#next unless defined $self->{_chart}[0]{$opts{column}};
		#** Rather, we should warning() that no graph is created for column $opts{column} in this report

		# ... This isn't really a warning, but a notice....
		# .... Maybe we need a notice handler....
		wadg::Errors::warning( 'N0003', $opts{filename} );
		my $graphs = new wadg::rm::Graphs( %opts );
		$graphs->graph($type);

	} # end if

} # end end_table


# ----------------------------------------------------------
# Sub: wadg::rm::Report::createNavMenu
#
# Args: $croParser, $htmlWriter
#	$croParser	Reference to a croParser object from which to 
#	          	make the navigation menu
#	$htmlWRiter	Reference to an htmlWriter object to write the 
#	          	menu with (style should be set)
#
# Description: This CLASS method creates the navigation menu
# contents and returns it. Any styles should be setup before 
# calling this function.
#
# ** I'd like to make this it's own object to pass to reports
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Nov17 Created a function to encapsulate the process JW
# 2000May19 Converted to use an HTMLWriter for rendering  JW
# 08Jan2002 Changed to use table for layout               JW
# 26Jul2002 Added support for NONE (0) as layout location JW
# 29Jul2002 Fixed so that blank Bullet_Image is not empty JW
# 19Aug2002 Changed bullet to use navbullet style         JW
# 28Oct2002 Removed nbsp after bullet. Cruft.             JW
# 30Oct2002 Added Top_Logo support                        JW
# 06Feb2003 Added File_Extension                          JW
# ----------------------------------------------------------
sub createNavMenu {
	my( $croParser, $nw, $config ) = @_;
	my $fileOut = '';
	my $NavMenuContent = '';

	#
	# Get the filenames and a template for the links
	#
	my %a;
	my $href = '<%%%>' . $config->{reports_File_Extension};
	if( $config->{File_Out} !~ /^LEFT|RIGHT|TOP|BOTTOM|0$/i ) {
		$a{target} = 'CONTENT';
		$fileOut = basename( $config->{reports_File_Out} );
	} # end if

	
	#
	# Insert the logo file content, or the default text unless doing TOP or BOTTOM
	#
	if( $config->{File_Out} !~ /^TOP|BOTTOM$/i ) {
		if( defined $config->{Top_Logo} && open( LOGOFILE, $config->{Top_Logo} ) ) {
			$NavMenuContent = join( '', <LOGOFILE> );
			close( LOGOFILE );
		} else {
			if( defined $config->{Top_Logo} ) {
				# If logo is defined and we got here, then we couldn't open
				# the file, so warn the user, but print the default text
				wadg::Errors::warning( 'W0007', $config->{Top_Logo} );
			} # end if
			$NavMenuContent .= $nw->h4( $LANG->val( 'Text', 'O0012' ) );
		} # end if
	} # end if
	

	#
	# Setup some variables to start including a template for the nav items
	#	
	my $item_template = '';
	my $imageBall = '';
	if( $config->{File_Out} =~ /^TOP|BOTTOM$/i ) {
		$item_template = '[&#160;' . $nw->span( {class => 'navitem'}, '<%%TITLE%%>' ) . '&#160;]&#160;';
	} else {
		if( defined $config->{Bullet_Image} && $config->{Bullet_Image} ) {
			$imageBall = $nw->img( {src => $config->{Bullet_Image}, border => 0, alt => '*'} );
		} # end if
		$item_template = $nw->tr( 
			$nw->td( {class => 'navbullet'}, '<%%IMG%%>' ),
			$nw->td( {class => 'navitem'}, '<%%TITLE%%>' ),
		);
	} # end if

	
	#
	# Add a layout table so wrapped titles are indented from bullets, unless TOP or BOTTOM
	#
	if( $config->{File_Out} !~ /^TOP|BOTTOM$/i ) {
		$NavMenuContent .= $nw->start_table( {cellpadding => 1, cellspacing => 0, border => 0, summary => 'Layout table' } );
	} # end if

	#
	# If single file put in top o' doc and change href template
	#
	if( $config->{One_File} != 0 ) {
		$a{href} = "$fileOut#top";
		$href = "$fileOut#<%%%>";
		my $t = $item_template;
		$t =~ s/<%%IMG%%>/$nw->a( \%a, $imageBall )/e;
		$t =~ s/<%%TITLE%%>/$nw->a( \%a, $LANG->val( 'Text', 'O0002' ) )/e;
		$NavMenuContent .= $t;
	} # end if

	#
	# Add each report type nav item
	#
	while( !$croParser->eof ) {
		my( $dataref ) = $croParser->nextReport();
		
		next if $dataref->[0] eq '';
		
		my( $link ) = split /[\012\015]+/, $$CONFIG{$dataref->[0]}{ShortName};
		$link =~ s/ //g;
		$a{href} = $href;
		$a{href} =~ s/<%%%>/$link/g;
		my $title = $$CONFIG{$dataref->[0]}{LongName};

		if( $title ) {
			my $t = $item_template;
			$t =~ s/<%%IMG%%>/$nw->a( \%a, $imageBall )/e;
			$t =~ s/<%%TITLE%%>/$nw->a( \%a, $title )/e;
			$NavMenuContent .= $t;

			# Remember to add quick report in just after General Summary, if desired
			if( ($dataref->[0] eq 'x') && (defined $config->{Summary_Rows}) ) { 
				( $link ) = split /[\012\015]+/, $$CONFIG{q}{ShortName};
				$link =~ s/ //g;
				$a{href} = $href;
				$a{href} =~ s/<%%%>/$link/g;
				$title = $$CONFIG{q}{LongName};
				$t = $item_template;
				$t =~ s/<%%IMG%%>/$nw->a( \%a, $imageBall )/e;
				$t =~ s/<%%TITLE%%>/$nw->a( \%a, $title )/e;
				$NavMenuContent .= $t;
			} # end if
		} # end if
	} # end while
	

	#
	# Close table if started
	#
	if( $config->{File_Out} !~ /^TOP|BOTTOM$/i ) {
		$NavMenuContent .= $nw->end_table();

		# Add email address if provided
		if( $config->{website}{Webmaster} ) {
			$NavMenuContent .= $nw->br() . $nw->br();
			$NavMenuContent .= $nw->p( $FORMATTER->formatMessage( $LANG->val( 'Text', 'O0006' ), $config->{website}{Webmaster} ) );
		} # end if
	} # end if

	# Reset current line marker
	$croParser->resetParser();
	
	return $NavMenuContent;
} # end createNavMenu


# ----------------------------------------------------------
# Sub: description
#
# Args: (None)
#
# Description: Writes out the description for the report at
# the top of the report section.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb24 Modified to read description from rdata file  JW
# 2000May06 Moved graph img tags to table_end method      JW
# ----------------------------------------------------------
sub description {
	my $self = shift;
	$self->{writer}->write( $self->{writer}->p( $self->{_CONFIG}{$self->{token}}{Description} ) );
} # end description



# ----------------------------------------------------------
# Sub: wadg::rm::Report::openReportFile [CLASS METHOD]
#
# Args: $filename
#		$filename	A filename to open and write to
#		$header  	An optional header to put at the top of the file
#
# Returns: An HTMLWriter object that will be used to write the 
# rest of the report content and should be closed with 
# closeReportFile. Returns undef on error.
#
# Description: Opens an output file for a report or reports.
# Inserts all the appropriate information at the head of the file.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb19 Creates to encapsulate report initialization  JW
# 2000Apr20 Converted to class method                     JW
# 2000May04 Added suport for header content               JW
# 2000May29 Converted to HTMLWriter use                   JW
# ----------------------------------------------------------
sub openReportFile {
	my( $fileName, $header, $letter ) = @_;
	local *reportFile;
		
	return undef unless open( reportFile, ">$fileName" );
	tied(%{$CONFIG})->get_report_styles( $letter );
  	my $rw = new wadg::HTMLWriter( -file => *reportFile,
  	                               -output => $$CONFIG{$letter}{Format}, 
  	                               -stylesheet => $$CONFIG{$letter}{_styles} );
	
	# Get character set
	my $cs = '';
	if( defined $LANG->val( 'Language', 'CharacterSet' ) ) {
		$cs = $rw->meta( {'http-equiv' => 'Content-Type', content => 'text/html; charset=' . $LANG->val( 'Language', 'CharacterSet' ) } );
	} # end if

	# If norobots, then make a tag
	my	$norobots = '';
	if( defined $$CONFIG{$letter}{No_Robots} && $$CONFIG{$letter}{No_Robots} != 0 ) {
		$norobots = $rw->meta( {name => 'ROBOTS', content => 'NOINDEX,NOFOLLOW' } );
	} # end if
	
	# If meta-refresh, then make a tag
	my $mr = $$CONFIG{$letter}{Meta_Refresh} || '';
	if( $mr eq '0' ) {
		$mr = '';
	} elsif( $mr ne '' ) {
		$mr = $rw->meta( {'http-equiv' => 'REFRESH', content => $mr } );
	} # end if
	
	# Get title for window and top of file
	my $title = $$CONFIG{website}{Title};

	# Get stylesheet if defined
	my $stylesheet = '';
	if( defined $$CONFIG{$letter}{Stylesheet} ) {
		if( $$CONFIG{$letter}{Stylesheet} =~ /\w+\s*\{\s*\w+\s*:.*}/ ) {
			$stylesheet = $rw->style( {type => 'text/css'}, $$CONFIG{$letter}{Stylesheet} );
		} elsif( $$CONFIG{$letter}{Stylesheet} ) {
			$stylesheet = $rw->link( { type => 'text/css', href => $$CONFIG{$letter}{Stylesheet}, rel => 'STYLESHEET' } );
		} # end if
	} # end if

	$rw->write( $rw->doctype( {-flavor => 'Strict'} ) );		# -flavor is ignored by HTML 3.2
	$rw->write( $rw->start_html( { lang => $LANG->val( 'Language', 'Symbol' )} ) );

	$rw->write( $rw->head( $cs,
	                       $rw->meta( {name => 'AUTHOR', content => "This page created by $$CONFIG{_INTERNAL}{'_TITLE'} $$CONFIG{_INTERNAL}{'_VERSION'}"} ),
	                       $norobots,
	                       $rw->title( $title ),
	                       $stylesheet,
	                     ) );

	$rw->write( $rw->start_body() );

	# Write title at the top of the report page
	if( defined $title ) {
		$rw->write( $rw->h1( $title ) );
	} # end if

	# Insert head from CRO file if any
	if( defined $header ) {
		$rw->write( $header . $rw->br() );
	} # end if

	return $rw;
	
} # end openReportFile

# ----------------------------------------------------------
# Sub: wadg::rm::Report::closeReportFile [CLASS METHOD]
#
# Args: $handle
#		$handle	A handle to an HTMLWriter file for the object
#		$footer	An optional footer to put at the bottom of the file
#
# Description: Finishes writing data to a report file and 
# closes the file associated with $handle.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb19 Created to encapsulate closing of the ouput 
#           file wether once for single file reports or 
#           every report for multi-file reports           JW
# 2000May04 Added suport for footer content               JW
# 2000May29 Converted to HTMLWriter use                   JW
# 17Jan2002 Only output time and range when defined       JW
# 10Mar2003 Fixed so no images written in STDOUT mode     JW
# ----------------------------------------------------------
sub closeReportFile {
	my( $rw, $footer, $letter ) = @_;

	# Output time and range (if values are defined)
	my( $gt, $dr ) = ('', '');
	$gt = $FORMATTER->formatMessage( $LANG->val( 'Text', 'O0003' ), $$GLOBALS{GenerationTime} ) 
		if defined $$GLOBALS{GenerationTime};
	$dr = $FORMATTER->formatMessage( $LANG->val( 'Text', 'O0004' ), $$GLOBALS{DataStart}, $$GLOBALS{DataEnd} ) 
		if defined $$GLOBALS{DataStart} && defined $$GLOBALS{DataEnd};
	if( $dr || $gt ) {
		$rw->write( $rw->p( {class => 'fineprint'}, $gt, $rw->br(), $dr, ) );
	} # end if
	
	# Insert logo file content or our logos
	if( ($$CONFIG{website}{Company_Logo} && open( LOGOFILE, $$CONFIG{website}{Company_Logo} )) ||
		 ($$CONFIG{reports}{File_Out} eq '-')
		 ) {
		$rw->write( <LOGOFILE> );
		close( LOGOFILE );
		$rw->write( 
			$rw->table( {border => '0', cellpadding => '5', cellspacing => '0', width => '95%'},
				$rw->tr( 
					$rw->td( 
						{colspan => 2, align => 'center', class => 'fineprint' }, 
						$rw->b( $LANG->val( 'Text', 'O0005' ) ),
						' ',
						$rw->a( {href => 'http://www.analog.cx/', target => '_top'}, $$GLOBALS{'AnalogVersion'} || 'Analog' ),
						' / ',
						$rw->a( {href => 'http://www.reportmagic.org/', target => '_top'}, "$$CONFIG{_INTERNAL}{_TITLE} $$CONFIG{_INTERNAL}{_VERSION}" )
					),
				)
			)
		);
	} else {
		if( defined $$CONFIG{website}{Company_Logo} ) {
			# If logo is defined and we got here, then we couldn't open
			# the file, so warn the user, but print the default logos
			# and remove defintion to warning only happens once.
			wadg::Errors::warning( 'W0005', $$CONFIG{website}{Company_Logo} );
			delete $$CONFIG{website}{Company_Logo};
		} # end if
		my $imageDir = $$CONFIG{$letter}{Image_Dir} || '';
		$rw->write( 
			$rw->table( {border => '0', cellpadding => '5', cellspacing => '0', width => '95%'},
				$rw->tr( $rw->td( {colspan => 2, align => 'LEFT'}, $rw->b( $LANG->val( 'Text', 'O0005' ) ) ) ),
				$rw->tr( 
					$rw->td( {align => 'LEFT'}, 
						$rw->a( {href => 'http://www.analog.cx/', target => '_top'}, 
							$rw->img( {src => $imageDir . 'analogo.png', align => 'MIDDLE', alt => 'Analog logfile analyser.', border => 0} ),
						),
						'&#160;',
						$rw->a( {href => 'http://www.analog.cx/', target => '_top'}, ucfirst($$GLOBALS{'AnalogVersion'}  || 'Analog') )
					),
					$rw->td( {align => 'LEFT'}, 
						$rw->a( {href => 'http://www.reportmagic.org/', target => '_top'},
							$rw->img( {src => $imageDir . 'rmlogo.png', align => 'MIDDLE', alt => 'Report Magic statistics formatting by Wadsack-Allen.', border => 0} ),
						),
						'&#160;',
						$rw->a( {href => 'http://www.reportmagic.org/', target => '_top'}, "$$CONFIG{_INTERNAL}{_TITLE} $$CONFIG{_INTERNAL}{_VERSION}" ),
					)
				),
			)
		);
	} # end if

	# -- Output footer, if any
	if( defined $footer ) {
		$rw->write( $footer . $rw->br() );
	} # end if

	$rw->write( $rw->end_body() );
	$rw->write( $rw->end_html() );

	return close $rw->{file};
} # end closeReportFile





##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################


# ----------------------------------------------------------
# Sub: _format_data_label
#
# Args: $data
#	$data	The data item label to be formatted
#
# Description: Formats the data label according to the style 
# of this report. Subclassed by each report type.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# 09Jan2002 Changed charset conversion only on latin-1    JW
# ----------------------------------------------------------
sub _format_data_label {
	my $self = shift;
	my( $data ) = @_;

	my $cropChar = $self->{_CONFIG}{$self->{token}}{Truncate} || '';
	my $elip = $self->{_LANG}->val( 'Symbols', 'ellipsis' );
	
	# Apply formatting
	my $cropLineData = $data;
	if( ( $cropChar ne '' )  && ( length($data) > $cropChar ) ) {
		$cropLineData = substr( $data, 0, $cropChar ) . $elip;
	} # end if

	#
	# First decode the point, in case it contains encoding.
	# Then encode the point in case it doesn't
	# Only do this if the character set it iso-8859-1 though, since 
	# HTML::Entities only supports that charcter set.
	# [Thanks to Jonas Smedegaard for the patch]
	my $charset = $self->{_LANG}->val( 'Language', 'CharacterSet' ) || '';
	if( $charset eq "iso-8859-1" ) {
		HTML::Entities::decode($cropLineData);
		HTML::Entities::encode($cropLineData);
		# - Do this too. Even though it looks weird, it's the 'proper' way to 
		#   write CGI links in HTML (SEE RFC 1866)
		# - Also it helps avoid cross-scripting vulnerabilities
		HTML::Entities::decode($data);
		HTML::Entities::encode($data);
	} # end if

	if( defined $self->{_CONFIG}{$self->{token}}{SmallFont} ) {
		$cropLineData = $self->{writer}->span( {class => 'smallfont'}, $cropLineData );
	} # end if

	return $self->__format_data__include_links( $data, $cropLineData );

} # end _format_data_label



# ----------------------------------------------------------
# Sub: __format_data__include_links
#
# Args: $link_data, $display_data
#	$link_data	The value to of the data item to link to.
#	$display_data	The value if the displayed item to be linked
#
# Description: This is called by _format_data_label to 
# make a linked label. Returns a single data item including 
# the link.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Mar09 Uses a more generic matching for URLs that 
#           helps keep text output from being linked      JW
# 2000Apr27 Created method based on previous subs         JW
#           Added support for list of matches to link     JW
# 2000Jun16 Added '/' for non-url links                   JW
# 21Feb2003 Support for Analog Crawler links              JW
# 20Mar2003 Fixed cross-scripting hole in Crawler links   JW
# 28Mar2003 Fixed bugs in linkable items detection        JW
# ----------------------------------------------------------
sub __format_data__include_links {
	my $self = shift;
	my( $link_data, $display_data ) = @_;
	my $linktype = quotemeta( $self->{_CONFIG}{$self->{token}}{IncludeLinks} || '' );

	# If it doesn't look like a URL link that don't bother linking
	# This should be quite strict to avoid cross-scripting holes
	# Actually, not sure that this is all that necessary, as even cross-scripted
	# stuff will get HTML encoded before being written as a URL. 
#	unless( $link_data =~ m{^([\w.+\-]+://[\w.-]+)?(/[\w/#~:.?+=&%@\\-]*)$}oi ) {
	# Disabled. This is not really working and not all that valuable. All it does
	# is make sure things that don't look like URLs aren't linked. That reduces
	# the possibility the RM can be leverages for unkown or future protocols with
	# different link patters. Anyway, the linked item should be responsible for
	# not opening Cross-scripting or other CGI holes that this was meant to avoid
	# propogating
	
	# If it's a [root directory] entry it should be linked to root
	# But don't link anything that's a [not listed: #]
	if( $link_data =~ /^\[.+[^\s\d]\]$/ ) {
		$link_data = '/';
	} elsif( $link_data =~ /^\[.+:\s\d+\]$/ ) {
		return $display_data;
	} # end if


	## Don't use 'if defined' here 'cause after quotemeta, $linktype is always defined!
	if( $linktype ) {
		# - Convert wildcards in $linktype to regexp and restore commas
		$linktype =~ s/\\\,/\,/g;
		$linktype =~ s/([^\\])\\\*/$1\.\*/g;
		$linktype =~ s/^\\\*/\.\*/g;
		$linktype =~ s/([^\\])\\\?/$1\./g;
		$linktype =~ s/^\\\?/\./g;

		# Check if it matches the IncludeLinks spec.
		foreach( split( ',', $linktype) ) {
			if( $link_data =~ /^$_$/ || $link_data =~ /\($_\)$/ ) {
				my $M = $&;		# Get the part of the data that matched the pattern
				           		## NOTE: This is an expensive operation. If we can do
									##       this differently we could speed things up
	
				# - Prepend the webiste URL if defined and this is a relative link.
				my $web_root = '';
				if( (defined $self->{_CONFIG}{website}{Base_URL}) && ($link_data !~ m#^\w+://#) ) {
					$web_root = $self->{_CONFIG}{website}{Base_URL};
				} # end if
	
				if( $link_data eq $M || $link_data eq '/' ) {
					$display_data = $self->{writer}->a( { href => $web_root . $link_data, target => '_top' }, $display_data );
				} else {
					# Fix the link to not include the parens
					$M = substr( $M, 1, length($M) - 2 );
					# Link only the part that matches
					$display_data =~ s/\Q$M/$self->{writer}->a( {href => $web_root . $M, target => '_top'}, $M )/e;
				} # end if
				
				# If we found a match, then jump out
				last;
			} # end if
		} # end foreach
		
	} # end if

	return $display_data;
} # end __format_data__include_links



# ----------------------------------------------------------
# Sub: _format_data_item
#
# Args: $data, $col
#	$data The data item to be formatted
#	$col  The column type
#
# Description: Formats the data item according to the style 
# of this report for the graph. Subclassed by each report type.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# 14Jun2001 Added $col and basic Formatting               JW
# 29Jul2002 Included support for legacy Number and Time   JW
# 14Aug2002 Stopped double formatting of TimeFormat       JW
# 26Nov2002 Added support for Show_Bytes_As setting       JW
# ----------------------------------------------------------
sub _format_data_item {
	my $self = shift;
	my( $data, $col ) = @_;
	
	# Get one of the Format specifiers.
	my $f = $self->{_CDATA}->val( $col, 'TimeFormat' );
	if( defined $f ) {
		# Time format has already been applied
		return $data;
	} else {
		$f = $self->{_CDATA}->val( $col, 'Format' );
		unless( defined $f ) {
			$f = $self->{_CDATA}->val( $col, 'NumberFormat' );
			$f = "number:$f" if defined $f;
		} # end if
	} # end unless
	
	# If there's a format then apply it here
	if( defined $f ) {
		my $b = $self->{_CONFIG}{$self->{token}}{Show_Bytes_As};
		if( ($f eq 'bytes') and defined($b) and $b ) {
			$data = $self->{_FORMATTER}->format_bytes( $f, $data, $b );
		} else {
			$data = $self->{_FORMATTER}->format_value( $f, $data );
		} # end if
	} # end if
	
	return $data;
} # end _format_data_item



# ----------------------------------------------------------
# Sub: _format_graph_label
#
# Args: $data
#	$data	The data item label to be formatted
#
# Description: Formats the data label according to the style 
# of this report for the graph. Subclassed by each report type.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# ----------------------------------------------------------
sub _format_graph_label {
	my $self = shift;
	my( $data ) = @_;

	# Remove HTML encoding
	$data =~ s/<[^>]+>//g;

	return $data;
} # end _format_graph_label

# ----------------------------------------------------------
# Sub: _write_summary
#
# Args: (None)
#
# Description: Writes out the summary information for the 
# report. Subclassed by most report types, this MUST close
# the table within its processing.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Built from parts in endReport                 JW
# ----------------------------------------------------------
sub _write_summary {
	my $self = shift;

	$self->end_table();
	$self->{writer}->write( $self->{writer}->p( ' ' ), $self->{writer}->hr() );
} # end _write_summary


# ----------------------------------------------------------
# Sub: _intialize
#
# Args: %parms
#	%parms	A set of named parameters to configure on init
#
# Description: Initializes the function. This is called by 
# the 'new' contstructor of this and all subclasses
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000APR25 Created method                                JW
# ----------------------------------------------------------
sub _initialize {
	my $self = shift;
	my( %parms ) = @_;

	# Parse named parameters
	my($k, $v);
	local $_;
	while( ($k, $v) = each %parms ) {
		$self->{$k} = $v;
	} # end while 

	# Declare some object variables
	$self->{_chart} = [];
	$self->{_summaries} = {};
	$self->{_shaded_row} = 0;

	return $self;
} # end _initialize

# ----------------------------------------------------------
# Sub: _data_row
#
# Args: @data
#	@data	The data to put in the row.
#
# Description: Writes out the data in the row of the table
# for a report. Calls the appropriate formatting methods for
# table and graph labels and data.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Originally created by Corey Kaye / DNS        CK
# 2000Apr25 Made a private method of Report Class         JW
# 2000May04 Converted to _data_row and extracted table, 
#           and filter components. Moved GeneralSummary 
#           stuff to that subclass                        JW
# 31May2001 Changed to handle new * columns in Analog 5   JW
# ----------------------------------------------------------
sub _data_row {
	my $self = shift;
	my ( @data ) = @_;
	
	# Filter column if it startes with '*' (analog 5+) or is only 'f' (analog 3 - 4) 
	if( ($self->{columns} eq 'f') || (substr($self->{columns}, 0, 1) eq '*') ) {
		$self->__filter_row( $self->{columns}, \@data );
	} else {
		my @columns = split( / */, $self->{columns} );
		$self->__table_row( $self->{_shaded_row}, \@columns, \@data );
	} # end if

} # end _data_row

# ----------------------------------------------------------
# Sub: __table_row
#
# Args: $row_color, $colref, $dataref
#	$row_color	The color (if any) to use for the row
#	$colref  	Reference to the list of column specs
#	$dataref 	Reference to the list of data to write to the row
#
# Description: Outputs data items into a table row.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May04 Created from sources in _data_row             JW
# 2000Nov28 Added support for Graph_Level setting         JW
# 29Jul2002 Simplified number formatting code             JW
# 10Mar2003 [not listed] now included in pie charts       JW
# ----------------------------------------------------------
sub __table_row {
	my $self = shift;
	my( $row_color, $colref, $dataref ) = @_;
	my( @columns ) = @{$colref};
	my( @data ) = @{$dataref};
	my %chartData;
	
	$row_color = 'alt' . ($row_color + 1);
	
	$self->{writer}->write( $self->{writer}->start_tr() );

	# Get index number for line
	my $num = @{$self->{_chart}} + 1;

	my $N_index = -1;
	my $l_index = -1;
	my $i;
	# ** Note that this only allows for a single index or level column in a row.
	#    and this gets the LAST one. [ JW]
	for( $i = 0; $i < @columns; $i++ ) {
		$N_index = $i if lc($self->{_CDATA}->val( $columns[$i], 'Type' )) eq 'index';
		$l_index = $i if lc($self->{_CDATA}->val( $columns[$i], 'Type' )) eq 'level';
	} # end for
	
	# If line contains an index column use that number and remove the column
	if( $N_index > -1 ) {
		$num = splice @data, $N_index + 1, 1;
		splice @columns, $N_index, 1;
	} # end if

	# If the line contains a level column and level != Graph_Level, then don't number
	if( ($l_index > -1) && ($data[$l_index + 1] ne $self->{_CONFIG}{$self->{token}}{Graph_Level}) ) {
		$num = '';
	} # end if

	# Don't number/chart 'not listed: ###' rows
	# Except we need to include [not listed] in the pie chart!
	my $graph_not_listed = 0;
	if( $data[0] =~ /^\[.+: \d+\]$/ ) {
		$num = '';
		$graph_not_listed = 1 if $self->{_CONFIG}{$self->{token}}{GraphType} =~ /pie/i;
	} # end if
	
	# Print line index, if there is one
	if( $num eq '' ) {
		$self->{writer}->write( $self->{writer}->td( {class => $row_color}, '&#160;' ) );
	} else {
		$self->{writer}->write( $self->{writer}->td( {class => $row_color}, "$num." ) );
	} # end if

	#
	# Now, iterate through data set and output rows.
	#
	$i = 0;
	foreach (@data) {
		my $c = 	$columns[$i - 1];
		$c .= '_' if $c eq uc($c);

		# Skip undefined data, level columns, and unknown columns
		next unless defined;
		
		if( $i ) {
			my $t = $self->{_CDATA}->val( $c, 'Type' ) || '';
			my $l = $self->{_CDATA}->val( $c, 'LongName' ) || '';
		   if( (lc($t) eq 'level') || ($l eq '') ) {
				$i++;
				next;
			} # end if
		} # end if

		#
		# Store data table for chart
		# Do this before value is formatted for output
		# Don't plot any non-numbered rows (num eq '') (unless it's 'not listed' and the chart is a pie chart!)
		# Remove HTML before sending to chart
		#
		if( ($num ne '') || $graph_not_listed ) {
			if( $i == 0 ) {
				$chartData{'name'} = $self->_format_graph_label( $_ );
				$chartData{'number'} = $num || '-';		# '-' to support [not listed] in pie charts
			} else {
				$chartData{$columns[$i - 1]} =  $_;
			} # end if
		} # end if
		
		#
		# Print line data
		#
		my %td = (class => $row_color, align => 'left');

		# If the data looks like a number then align right.
		# Don't format IP numbers though and don't right-align anything in column 0
		if( ($i > 0) && (/^[\d\.]+$/) && !(/\d+\.\d+\./) ) {
			$td{align} = 'right';
		} # end if
		
		# - If no value insert a &#160;, otherwise format appropriately
		if( $_ eq '' ) {
			$_ = '&#160;';
		} elsif( $i == 0 ) {
			$_ = $self->_format_data_label( $_ );
		} else {
			$_ = $self->_format_data_item( $_, $c );
		} # end if 

		$self->{writer}->write( $self->{writer}->td( \%td, $_ ) );
		$i++;
	} # end foreach

	if( defined $chartData{name} ) {
		push @{$self->{_chart}}, \%chartData;
	} # end if
	
	$self->{writer}->write( $self->{writer}->end_tr() );

} # end __table_row

# ----------------------------------------------------------
# Sub: __summary_row
#
# Args: $row_color, $colref, $dataref
#	$colref  	Reference to the list of column specs
#	$dataref 	Reference to the list of data to write to the row
#
# Description: Outputs summary items into a table row.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May04 Created from sources in _data_row             JW
# 20Dec2001 Fixed bug where summary label was formatted   JW
# 29Jul2002 Simplified number formatting code             JW
# ----------------------------------------------------------
sub __summary_row {
	my $self = shift;
	my( @columns ) = @{shift()};
	my( @data ) = @{shift()};

	$self->{writer}->write( $self->{writer}->start_tr() );

	# Print an empty cell for the index number column
	$self->{writer}->write( $self->{writer}->th( {class => 'total'}, '&#160;' ) );

	#
	# Now, iterate through data set and output rows.
	#
	my $i = 0;
	foreach (@data) {
		# Skip undefined data, index, level and unknown columns
		next unless defined;

		my $c = 	$columns[$i - 1];
		$c .= '_' if $c eq uc($c);

		if( $i && (
		    (lc($self->{_CDATA}->val( $c, 'Type' )) eq 'level') ||
		    ($self->{_CDATA}->val( $c, 'LongName' ) eq '')
		  )) {
			$i++;
			next;
		} # end if

		#
		# Print line data
		#
		my %th = (class => 'total', align => 'left');

		# If the data looks like a number then align right.
		# Don't format IP numbers though and don't right-align anything in column 0
		if( ($i > 0) && (/^[\d\.]+$/) && !(/\d+\.\d+\./) ) {
			$th{align} = 'right';
		} # end if
		
		# - If no value insert a &#160;, otherwise format appropriately
		#   (Don't format the summary data labels, though!)
		if( $_ eq '' ) {
			$_ = '&#160;';
		} elsif( $i ) {
			$_ = $self->_format_data_item( $_, $c );
		} # end if 

		$self->{writer}->write( $self->{writer}->th( \%th, $_ ) );
		$i++;
	} # end foreach

	$self->{writer}->write( $self->{writer}->end_tr() );

} # end __summary_row


# ----------------------------------------------------------
# Sub: __filter_row
#
# Args: $dataref
#	$column	The column spec for the filter row
#	$dataref	A reference to the filter data to write
#
# Description: Writes out filter rows to the report
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May04 Created from _data_row sources                JW
# 31May2001 Added new filter row types BT, FR, LR         JW
# 10Mar2003 Fixed bug with BT row killing summaries       JW
# ----------------------------------------------------------
sub __filter_row {
	my $self = shift;
	my( $column, $dataref ) = @_;

	# Process each type of column separately
	if( ($column eq 'f') || ($column eq '*f') ){
		$column = 'f';
		# Process the floor/sort through the the regular expressions
		# Iterate over each column of data (first one in null)
		my @out;
		shift @$dataref if $dataref->[0] eq '';
		
		# This is now fairly hard-coded. If there's no Active_Column defined, then 
		# set it based on the sort order of this report
		unless( defined $self->{_CONFIG}{$self->{token}}{Active_Column} ) {
			$self->{_CONFIG}{$self->{token}}{Active_Column} = $dataref->[1];
			$self->{_CONFIG}{$self->{token}}{Active_Column} .= '_' if $self->{_CONFIG}{$self->{token}}{Active_Column} eq uc($self->{_CONFIG}{$self->{token}}{Active_Column});
		} # end if
		
		
		my $w = 0;
		foreach( @$dataref ) {
			$w++;
			my $level = 1;
			my $match = $self->{_CDATA}->val( $column, "Col$w" . "_Match$level" ) || '';
			my @results;
			$out[$w - 1] = $self->{_CDATA}->val( $column, "Col$w" . "_LongName$level" ) ||'';
		
			# - Find out which re it matches 
			while( !( @results = /$match/ ) ) {
				if( $match eq '' ) {
					# There is no match so just output data
					$out[$w - 1] = $_;
					$level = 0;
					last;
				} # end if
				$level++;
				$match = $self->{_CDATA}->val( $column, "Col$w" . "_Match$level" ) || '';
				$out[$w - 1] = $self->{_CDATA}->val( $column, "Col$w" . "_LongName$level" ) || '';
			} # end while
		
			if( $level > 0 ) {
				# If there's a match, start replacing results text
				my $r;
				for $r ( 0 .. @results ) {
					my $rl = "Col$w" . '_Result' . $level . '_' . ($r + 1);
					my $ri = $results[$r];
					next unless defined $ri;
					# Go through the results replacement items only if they exist
					if( defined $self->{_CDATA}->val($column, $rl) ) {
						foreach ($self->{_CDATA}->val($column, $rl)) {
							my $t = $_;
							next unless defined $t;
							if( $ri eq '' ) {
								if( ($t) = /^\t(.*)$/ ) {
									$results[$r] = $t;
									last;
								} # end if
							} elsif( ($t) = /^[^\t]*$ri[^\t]*\t(.*)$/ ) {
								$results[$r] = $t;
								last;
							} # end if
						} # end foreach	
					} # end if
					# Now put replaced texts into output string
					$ri = $results[$r];
					my $rn = $r + 1;
					$out[$w -1] =~ s/\%$rn/$ri/g;
				} # end for -- $r
			} # end if
		} # end foreach
		
		# Now write output string
		$self->{writer}->write( $self->{writer}->p( {-class => 'smallfont'}, join( ' ', @out ) ) );
	} elsif( $column eq '*BT' ){
		# Put this into the summary section
		my( $dType ) = split /[\012\015]+/, $self->{_CONFIG}{$self->{token}}{ShortName};
		my $c = shift @$dataref;
		my $d = shift @$dataref;
		# Now insert the value from Analog
		$self->{_summaries}{$dType}{max}{BT} = 1;
		$self->{_summaries}{$dType}{max}{name} = $self->_format_data_label( $self->{_FORMATTER}->getDateString( @$dataref ) );
		$self->{_summaries}{$dType}{max}{$c} = $d;
	} elsif( $column eq '*FR' ){
		$self->{REPORTSPAN} = 1;
		$$GLOBALS{DataStart} = $dataref->[0];
	} elsif( $column eq '*LR' ){
		$self->{REPORTSPAN} = 1;
		$$GLOBALS{DataEnd} = $dataref->[0];
	} # end if
} # end __filter_row


# ----------------------------------------------------------
# Sub: _summarize
#
# Args: $point, @lineData
#	$point	The label for the current data set
#	@lineData	The data set
#
# Description: Builds the summary hashes for the data based 
# on the Active_Column.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created sometime in early 2000                JW
# 2000APR25 Made a private method of the Report class     JW
# 2000May06 Added total and count summaries               JW
# 05Jun2001 Added workaround for Analog's *BT column      JW
# 08Jan2002 Fixed bug where * columns were summarized     JW
# ----------------------------------------------------------
sub _summarize {
	my $self = shift;
	my( $point, @lineData ) = @_;

	my( $dType ) = split /[\012\015]+/, $self->{_CONFIG}{$self->{token}}{ShortName};
	my $active_col = substr($self->{_CONFIG}{$self->{token}}{Active_Column}, 0, 1);
	my $active_value = $lineData[index( $self->{columns}, $active_col )] || '';
	
	# Don't summarize this row if it's a [not listed: xxx] row, not numeric or a meta-row
	if( $point !~ /^\[.+: \d+\]$/ && $active_value =~ /^\d+$/ && ($self->{columns} ne 'f') && (substr($self->{columns}, 0, 1) ne '*')) {
		# If this is bigger than the max then store as the max (unless Analog gave it to us)
		if( !defined($self->{_summaries}{$dType}{max}{BT}) &&
		    ( !defined($self->{_summaries}{$dType}{max}{$active_col}) ||
		      $self->{_summaries}{$dType}{max}{$active_col} < $active_value 
			 ) 
		  ) {
			$self->{_summaries}{$dType}{max}{name} = $self->_format_data_label( $point );
			wadg::rm::CROParser::splitColumns( $self->{columns}, \%{$self->{_summaries}{$dType}{max}}, @lineData );
		} # end if
		# Store the total and count of values
		$self->{_summaries}{$dType}{count}++;
		my $i;
		for( $i = 0; $i < @lineData; $i++ ) {
			if(defined($lineData[$i]) && $lineData[$i] =~ /^\d+$/ ) {
				$self->{_summaries}{$dType}{total}{substr($self->{columns}, $i, 1)} += $lineData[$i];
			} # end if
		} # end for
	} # end if

} # end _summarize



# ----------------------------------------------------------
# Sub: _format_data_columns
#
# Args: @data
#	@data   	The data to 
#
# Description: Separates column data from datapoint name
# If datapoint is more than one field then uses getDateString 
# to make a date and puts it on the end. The returned array 
# is all the data columns plus one column for the datapoint name.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb26 Created function                              JW
# 2000Mar21 Renamed to formatDataColumns                  JW
# 2000Apr25 Converted to private method of Report class   JW
# 31May2001 Special consideration for '*' columns         JW
# ----------------------------------------------------------
sub _format_data_columns {
	my $self = shift;
	my( @dataCols ) = @_;
	my( $pointName, @pointCols );
	my( $l, $j ) = (0, 0);
	my @dCols = ();
	my @rList = ();
	my @columns = split( / */, $self->{columns} );
	
	# Handle '*' columns specially
	my @saved = ();
	if( $columns[0] eq '*' ) {
		@columns = ( $self->{columns} );
		if( $columns[0] eq '*f' ) {
			$columns[0] = 'f';
		} # end if
		@saved = splice( @dataCols, 0, $self->{_CDATA}->val( $columns[0], 'Saved' ) ) if defined $self->{_CDATA}->val( $columns[0], 'Saved' );
	} # end if;
	
	#
	# Iterate through column specs and concatenate any date format columns
	#
	my $extra = @dataCols;
	foreach ( @columns ) {
		$_ .= '_' if $_ eq uc && substr($_,0,1) ne '*';
		
		$l = $self->{_CDATA}->val( $_, 'Width' );

		if( defined $l && $l > 1 ) {
			# -- Sometimes, "wide" columns can be less than their defined width 
			#    (e.g. D, when the date undefined in Analog <= 4.1) so we need 
			#    to limit the actual width. However, filter columns use the full 
			#    width of the row, so set the width to at most the width of the 
			#    data minus one only if it over runs the width of the row. 
			if( $l > @dataCols - $j ) {
				$l = @dataCols - $j - 1;
				$l++ if $self->{_CDATA}->val( $_, 'Type' ) eq 'Filter';
			} # end if

			# -- Pull out all the columns for the 'wide' column
			$extra -= $l;
			@pointCols = splice( @dataCols, $j, $l );
			# -- Now format those columns into a single value into @dCols
			my $fmt = $self->{_CDATA}->val( $_, 'TimeFormat' ) || '';
			if( $fmt ne '' ) {
				# Handle unparsable dates by a '--' mark, otherwise format them
				if( grep( /\D/, @pointCols ) || (grep {!defined} @pointCols) ) {
					push( @dCols, '--' );
				} else {
					$pointName = $self->{_FORMATTER}->getDateString( @pointCols );
					# For anything formatted on the column level do it here
					if( $fmt ne 'report' ) {
						$pointName = $self->{_FORMATTER}->formatDate( $fmt, $pointName );
					} # end if
					push( @dCols, $pointName );
				} # end if
			} else {
				push( @dCols, @pointCols );
			} # end if
		} else {
			$extra--;
			push( @dCols, $dataCols[$j] );
			$j++;
		} # end if
	} # end for each

	if( $extra > 0 ) {
		undef( @pointCols );
		while( $extra ) {
			$pointName = pop( @dataCols );
			@pointCols = ($pointName, @pointCols );
			$extra--;
		} # end while
		$pointName = $self->{_FORMATTER}->getDateString( @pointCols );
		unshift @dCols, $pointName;
	} elsif( substr($columns[0],0,1) ne '*') {
		#
		# The problem here, of course, is that the reports really expect
		# there to be an extra of 1, so we need to fake it by inserting 
		# a blank $point before the data. This is because, the split 
		# function (in &splitline) doesn't read a non-value after a 
		# trailing separator. Is this a bug in the split implementation?
		# I kind of think so. [JW]
		#
		unshift @dCols, '';
	} # end if
	unshift @dCols, @saved;
	
	return @dCols;
} # end _format_data_columns

# ----------------------------------------------------------
# Sub: _get_graph_filenames
#
# Args: (None)
#
# Description: Returns a list of filenames for the defined
# graphs for the current report. This is called at the IMG
# tag insertion point and graph file creation point so that
# the filenames are guaranteed to coincide. Returns undef
# if no graph data exists for the currently defined graphs 
# and the Active_Column.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May07 Created to encapsulate filename generation    JW
# 27Feb2003 Return () when sending to stdout w/o Path_To  JW
# ----------------------------------------------------------
sub _get_graph_filenames {
	my $self = shift;
	my @names;
	my $type;
	my $format = $self->{_CONFIG}{graphs}{Format} || 'png';


	##
	## We aren't going to go this right now. We'll just
	## doc that the CGI interface is not transaction-safe
	## Anyway, MD5(time.rand) is the way to make this unique!
	##
	
	# Get the session code 
	#   -- local time and PID should be enough, but add a random number 
	#      for extra transactability. Results is 32-byte key capable of
	#      3.4e+38 simultaneous sessions!
	# if( ($self->{_CONFIG}{reports}{File_Out} eq '-') && (!defined $self->{Session_ID}) ) {
		# 
		# #
		# # ******* SECURITY ISSUE *******
		# # Using the PID as part of the session Id can be a security breach. Better
		# # To just use random data
		# #
		# 
		# # Now, pack it and shuffle it to mess it up a bit.
		# my @chrs = split( //, pack( 'h', int( rand( 1000000.99999 ) ), ARRAY(localtime), $$ ) );
		# splice( @chrs, 32 );
		# for( 0 .. (length($self->{Session_ID}) - 1) ) {
			# my $t = $chrs[$_];
			# my $r = rand( @chrs );
			# $chrs[$_] = $chrs[$r];
			# $chrs[$r] = $chrs[$t];
		# } # end for
		# $self->{Session_ID} = join( '', @chrs );
	# } # end if

	
	#
	# When output is STDOUT, return an empty list (i.e. no graphs)
	# unless Path_To is set. Otherwise we have no place to write them
	#
	return () if ($self->{_CONFIG}{reports}{File_Out} eq '-') && !exists $self->{_CONFIG}{graphs}{Path_To};

	
	#
	# Get a basename -- use the first report-name listed in configs
	#
	my( $filename ) = split /[\012\015]+/, $self->{_CONFIG}{$self->{token}}{ShortName};

	
	#
	# Run through each defined type
	#
	my $ac = substr( $self->{_CONFIG}{$self->{token}}{Active_Column}, 0, 1 );
	foreach $type ( split( ',', $self->{_CONFIG}{$self->{token}}{GraphType} || '' ) ) {
		$type =~ s/^\s+//;
		$type =~ s/\s+$//;
		if( ($type =~ /pie/i && index( $self->{columns}, lc($ac) ) > -1) ||
		    ($type !~ /pie/i && index( $self->{columns}, uc($ac) ) > -1) ) {
			push( @names, $filename . '_' . lc($type) . '.' . lc($format) );
		} # end if
	} # end foreach

	return @names;
	
} # end _get_graph_filenames


# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
