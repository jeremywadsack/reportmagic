############################################################
#
# Module: wadg::HTMLWriter
#
# Created: 07.May.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 2000,2002 Wadsack-Allen. All rights reserved.
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
# 2000.May.16 Limited cascade support through context     JW
# 2000.May.16 Moved specific output styles to subclasses  JW
# 2000.May.20 Added support for hash ref for -stylesheet  JW
############################################################
package wadg::HTMLWriter;

=head1 NAME

HTMLWriter - An HTML Writing class with CSS support

=head1 SYNOPSIS

 use wadg::HTMLWriter;
 $w = new HTMLWriter( -stylesheet => 'styles.css', -output => 'HTML 3.2' );
 print $w->start_html;
 print $w->head( $w->title( 'Stylesheets for old browsers' ) );
 print $w->h1( 'Stylesheets for old browsers' );
 print $w->p( qq[This page was built with a style sheet, but 
                 no stylesheet is used in the output] );
 print $w->end_html;

=head1 DESCRIPTION

A class that provides familiar, easy-to-use HTML element methods,
and understands stylesheets. In particular, a stylesheet can be applied and the
HTMLWriter will output using styles (for HTML 4.0 or XHTML output) or using <FONT>
tags for (HTML 3.2 output).

=head1 METHODS

Most of the methods for HTMLWriter are basic HTML elements (e.g. $w->h1), just handled 
differently depending on the output requirements. They closely correspond to HTML tags 
and are not documented here explicitly.

The following methods are of special interest in HTMLWriter:

=over 4

=cut 

use strict;

BEGIN {
	use vars       qw( $VERSION @ISA );

	$VERSION = do { my @r = (q$Revision: 2.00 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw();

} # end BEGIN

# non-exported package globals go here
use vars      qw( $AUTOLOAD @EMPTY );

# List of paramters that may be empty (e.g. have no end tag). This is loaded 
# into the objects space at $self->{_EMPTY} so that it can be overridden in 
# the constructor of subclasses (e.g. $self->{_EMPTY} = qw(...))
# This one is HTML 4+ including XHTML 1.0
@EMPTY = qw( BASE META LINK HR BR PARAM IMG AREA INPUT COL FRAME );


############################
## The object constructor ##
############################

=item $w = new HTMLWriter( -output => 'HTML 3.2', -stylesheet => 'styles.css' );

=item $w = new HTMLWriter::HTML_3_2( -stylesheet => 'styles.css' );

Builds a new HTMLWriter object. In the first syntax style, the HTMLWriter will look 
for a subclass of itself that matches "::HTML_3_2", "::HTML_3" or "::HTML" and return 
that if found. Otherwise it will return the default HTMLWriter class. In the second format 
you are specifying the subclass (i.e. version) explicitly. If the subclass doesn't exist, 
then you will get a compile-time error.

The HTMLWriter objects support the following named parameters in the constructor:

 -stylesheet        A scalar containing a filename, stylesheet data, a handle to 
                    a stylesheet file (already open), or a reference to a hash of a hash 
                    containing stylesheet entries. Content can can also be pased  
                    through the style tag method.
 -output            An output format specifier string. Valid strings are:
                      'HTML 3.2'  Outputs HTML 3.2 compliant elements
                      'XHTML 1.0' Outputs XHTML 1.0 compliant elements using styles
 -file              A handle to an open file, pipe, or other output stream to which 
                    write method calls will print their arguments.


The HTMLWriter objects have the following public properties:

	output_type      Corresponds to the 'word' part of the output format specifier. In the 
	                 supported formats this is HTML or XHTML
	output_version   Corresponds to the 'number' part of the output format speficier. For 
	                 example, '3.2', '4.01', or '1.0'
	CONTEXT          This is a stack representing the current HTML context. While this is 
	                 mainly used internally for cascade support, it is exposed as a very simple
	                 syntax checker: after writing the output you can check $w->{CONTEXT} to 
	                 see if any elements haven't been closed (like </BODY> or </HTML>). Of 
	                 course this will auto-close any contained elements, so if you call 
	                 $w->end_html then everything else will be closed.

=cut

sub new {
	my $proto = shift;
	my %parms = @_;
	my $self = {};
   bless( $self, ref $proto || $proto );
	# Parse -output parameter to load subclass if possible
	if( defined $parms{-output} ) {
		# Get type and version
		my($out_type) = $parms{-output} =~ /^(\w+)\s+/;
		my($out_version) = $parms{-output} =~ /^\w+\s+([\d\.]+)/;

		# Remove it so we don't get an endless loop
		delete $parms{-output};

		# Convert $out_version to package legal characters
		$out_version =~ s/\./_/;
		
		# Get full package name, major version package name and type package name
		my $full_package = "wadg::HTMLWriter::$out_type" . '_' . $out_version;
		my $major_package = $full_package;
		   $major_package =~ s/_\d+$//;
		my $type_package = "wadg::HTMLWriter::$out_type";

		# Now get the subclass for the version, if any
		if( $full_package->isa( 'wadg::HTMLWriter' ) ) {
			$self = $full_package->new( %parms );
		} elsif( $major_package->isa( 'wadg::HTMLWriter' ) ) {
			$self = $major_package->new( %parms );
		} elsif( $type_package->isa( 'wadg::HTMLWriter' ) ) {
			$self = $type_package->new( %parms );
		} # end if

		# Store the version and type
		$self->{output_type} = $out_type;
		$self->{output_version} = $out_version;
	} # end if
	
	# Parse other named parameters
	foreach ( keys %parms ) {
		my( $k ) = /^-?([^-].*)$/;   # Remove leading '-', if any
		if( $k eq 'stylesheet' ) {
			$self->_parse_stylesheet( $parms{$_} );
		} else {
			$self->{$k} = $parms{$_};
		} # end if
	} # end while 

	# Setup object variables
	$self->{CONTEXT} = [];
	$self->{_EMPTY} = \@EMPTY;
	$self->{file} = \*STDOUT unless defined $self->{file};

	return $self;
} # end new

##########################
##                      ##
##    PUBLIC METHODS    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: AUTOLOAD
#
# Args: (Anything)
#
# Description: Called by the system for undefined methods.
# This just pushes the tag (undefined method) name and the 
# parameters to our _auto_tag method which can be called 
# from other (defined) methods or from subclasses or can 
# be overridden in subclasses
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May16 Moved processing to _auto_tag                 JW
# ----------------------------------------------------------
sub AUTOLOAD {
	my $self = shift;
	my $name = $AUTOLOAD;
	   $name =~ s/.*://;
	return $self->_auto_tag( $name, @_ );
} # end AUTOLOAD


=item doctype

Outputs the !DOCTYPE header for the current output style. In the 
default inplementation this just outputs something like this:

 <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML">

In subclasses (or formats) this outputs with the proper version.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub doctype {
	my $self = shift;
	return '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML">';
} # end doctype



=item head( \%attrs, @content );

Outputs a <HEAD> element set, including the content, if any. 
In addition, this will include a <STYLE> tag for the 
C<-stylesheet> contructor parameter, if one was given.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May20 Added <STYLE> to the end of the content       JW
# ----------------------------------------------------------
sub head {
	my $self = shift;
	my @content = @_;
	push @content, $self->style( {type => 'text/css'}, $self->_write_stylesheet( $self->{_styles} ) ) if defined $self->{_styles};
	return $self->_auto_tag( 'head', @content );
} # end head

=item end_head();

Outputs a </HEAD> end tag and includes a <STYLE> tag for the 
C<-stylesheet> contructor parameter, if one was given.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May20 Added <STYLE> to the end of the content       JW
# ----------------------------------------------------------
sub end_head {
	my $self = shift;
	return $self->style( {type => 'text/css'}, $self->_write_stylesheet( $self->{_styles} ) ) . $self->_auto_tag( 'end_head' );
} # end end_head


=item comment (@content)

Outputs an HTML comment with the data enclosed
(e.g. "<--- My comments --->").

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May29 Created method                                JW
# ----------------------------------------------------------
sub comment {
	my $self = shift;
	my( @content ) = @_;
	my $res = '';

	if( ref($_[0]) eq 'ARRAY' ) {
		# Do this whole thing for each element
		$res = join '', map( "<!-- $_ -->", @{$_[0]} );
	} else {
		$res = '<!-- ' . join( '', @_ ) . ' -->';
	} # end if

	return $res;
} # end comment


=item write (@LIST)

This is just a handy method for printing @LIST through the object
context. For example, you could write an HTML page like this:

 $w->write( $w->html( $w->head( $w->title( "My page) ), 
                      $w->body( $w->h1( "My web page" ),
                                $w->p( 'This is my web page.' )
                              )
                    )
          );
          
This will print to STDOUT unless a C<-file> option was set on the 
constructor (or the object's C<file> property was set before the call).

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May18 Created method                                JW
# 22Mar2001 Silently fails when file property is undef    JW
# ----------------------------------------------------------
sub write {
	my $self = shift;
	my( @list ) = @_;
	my $f = $self->{file};
	return unless defined $f;
	print $f @list;
} # end write

=item get_styles()

Returns a reference to a hash containing the styles in use 
in the writer

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 22Mar2001 Exposed to allow hash access to the styles    JW
# ----------------------------------------------------------
sub get_styles {
	my $self = shift;
	return $self->{_styles};
} # end get_styles

# ----------------------------------------------------------
# Sub: DESTROY
#
# Description: Defined so it isn't called into AUTOLOAD
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May18 Created method                                JW
# ----------------------------------------------------------
sub DESTROY {
	return;
} # end DESTROY


##########################
##                      ##
##   PRIVATE METHODS    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: _auto_tag
#
# Args: $name, @parms
#	$name	The name of the tag to generate
#	@parms	Any parms passed to the call
#
# This calls _make_tag for instance specific formatting of
# tags. Any non-standard tags (e.g. <BR>,<br />) should be 
# handled in their own subs.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 25Apr2001 Fixed warning about unititialized @_          JW
# ----------------------------------------------------------
sub _auto_tag {
	my $self = shift;
	my $name = shift;
	my $res = '';
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	if( $name =~ /^start_(.*)/ ) {
		my $tag = $1;
		$res = $self->_make_tag( $tag, \%attrs );
		push @{$self->{CONTEXT}}, $tag;
	} elsif( $name =~ /^end_(.*)/ ) {
		my $tag = $1;
		if( grep /^$tag$/i, @{$self->{CONTEXT}} ) {
			while( $#{$self->{CONTEXT}} && ($self->{CONTEXT}[$#{$self->{CONTEXT}}] ne $tag) ) {
				#* carp "Forcing output of end_$self->{CONTEXT}[$#{$self->{CONTEXT}}].";
				#* $res .= $self->_make_tag( $self->{CONTEXT}[$#{$self->{CONTEXT}}] );
				pop @{$self->{CONTEXT}};
			} # end while
			pop @{$self->{CONTEXT}};
		} else {
			#* carp "end_$tag() encountered with no matching start_$tag."
		} # end if
		$res .= $self->_make_tag( $tag );
	} elsif( !@_ && grep( /^$name$/i, @{$self->{_EMPTY}} ) ) {
		# If no content and this can be an empty tag, then only do 
		# the start tag. This is an HTML (not XHTML) implementation.
		$res = $self->_make_tag( $name, \%attrs );
	} else {
		# Get tags
		my $start = $self->_make_tag( $name, \%attrs );
		my $end = $self->_make_tag( $name );

		if( @_ ) {
			if( ref($_[0]) eq 'ARRAY' ) {
				# Do this whole thing for each element
				$res = join '', map( "$start$_$end", @{$_[0]} );
			} else {
				$res = $start . join( '', @_ ) . $end;
			} # end if
		} else {
			$res = $start . $end;
		} # end if
	} # end if

	return $res;
} # end _auto_tag

# ----------------------------------------------------------
# Sub: _make_tag
#
# Args: $tag, %attrs
#	$tag	The name of the element
#	$attrs	The reference to a hash of name value pairs for 
#	      	the attributes. For an opening tag, this is a 
#	      	hash or empty hash. For a closing tag this is not 
#	      	given (undef).
#
# Description: Internal method to create tags in the desired
# format. All attribute values are quoted here in double 
# quotes which is compatible for all (current) styles. 
# However, this may be overridden in subclasses to change other
# aspects of the output.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _make_tag {
	my $self = shift;
	my( $tag, $attrs ) = @_;
	my $ret;

	if( (defined $attrs) && (ref($attrs) eq 'HASH') ) {
		$ret = "<$tag";
		foreach ( keys %{$attrs} ) {
			my $val = $attrs->{$_};
			s/^-//; # Remove initial '-' if any
			s/_/-/; # Convert '_' to '-'
			$ret .= " $_=\"$val\""
		} # end foreach
		$ret .= '>';
	} else {
		$ret = "</$tag>";
	} # end if


	return $ret;
} # end _make_tag


# ----------------------------------------------------------
# Sub: _parse_stylesheet
#
# Args: $stylesheet
#	$stylesheet	A file handle, glob ref, file name or stylesheet
#              content to parse and apply to all output.
#
# Description: Loads and parses a style sheet for output 
# modifications. On success returns a ref to the stylesheet 
# hash. On failure returns undef.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 27Jan2001 Fixed bugs in parsing ".class elm" selectors  JW
# 11Apr2001 Added fix for comments in stylesheets         JW
# ----------------------------------------------------------
sub _parse_stylesheet {
	my $self = shift;
	my( $stylesheet ) = @_;
	my $styles;

	# Find out what kind of thingy $stylesheet is
	# Adapted from CGI.pm (C) Lincoln Stein
	return undef unless defined $stylesheet;

	my $handle;
	# If it's any kind of file, make a handle
	if( (UNIVERSAL::isa( $stylesheet, 'GLOB' )) || (UNIVERSAL::isa( $stylesheet, 'GLOB' )) ) {
		$handle = $stylesheet;
	} elsif( $stylesheet =~ /^\S+[\':]\S+$/ ) {
		$handle = $stylesheet if defined fileno( $stylesheet );
	} elsif( !ref( $stylesheet ) && ($stylesheet !~ /\s/) ) {
		my( $caller, $package ) = ( 1, '' );
		while( $package = caller( $caller++ ) ) {
			my( $var ) = "$package\:\:$stylesheet"; 
			if( defined fileno( $var ) ) {
				$handle = $var;
			} # end if
		} # end while
	} # end if
	
	# Now we have acccess to the content to read it into $styles
	if( defined $handle ) {
		# If it's a handle then read it
		$styles = join( '', <$handle> );
	} elsif( ref( $stylesheet ) eq 'HASH' ) {
		$self->{_styles} = $stylesheet;
	} elsif( open( STYLE, $stylesheet ) ) {
		# If it's a filename, then open it, read it, and close it
		$styles = join( '', <STYLE> );
		close( STYLE );
	} elsif( $stylesheet =~ /^\s*[\.\#\w]+\s*\{/ ) {
		# Must be content
		$styles = $stylesheet;
	} # end if

	if( defined $styles ) {
		# Remove any comments, first.
		# ** This doesn't allow embedded /* ... */ comments!
		# ** This means anything following // is a comment, even in quotes!
		$styles =~ s{/\*.*?\*/}{}gs;
		$styles =~ s{//.*$}{}gm;

		# Parse $styles into our style sheet hashes
		# If it's not a text/css style, then return undef -- we can't parse it
		$styles =~ tr/\012\015//;
		return undef unless $styles =~ s/(\w|[\.\#\w][^\{]*[^\s\{])\s*\{([^\{\}]+)}\s*/$self->{_styles}{lc($1)}=$2/ge;

		my $elm;
		foreach $elm ( keys %{$self->{_styles}} ) {
			foreach ( split( /\s*;\s*/, $self->{_styles}{$elm} ) ) {
				if( /^\s*([^:\s]+)\s*:\s*(.*)\s*$/ ) {
					$self->{_styles}{$elm} = {} unless ref $self->{_styles}{$elm};
					$self->{_styles}{$elm}{lc($1)}=$2;
					$self->{_styles}{$elm}{lc($1)} =~ s/\s+$//;
				} # end if
			} # end foreach
		} # end foreach
	} # end if
	
	return $self->{_styles};
} # end _parse_stylesheet

# ----------------------------------------------------------
# Sub: _write_stylesheet
#
# Args: $style_ref
#	$style_ref	A reference to a hash of hash containing the styles
#
# Description: Converts a hash of hash style package into a scalar
# containg CSS format style sheet content. If the object property
# 'pretty' is set, then this will output in a nice, readable format.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May20 Created method. Replaces _pretty_style        JW
# ----------------------------------------------------------
sub _write_stylesheet {
	my $self = shift;
	my( $style_ref ) = @_;
	my $stylesheet;
	
	my $elm;
	foreach $elm ( keys %{$style_ref} ) {
		$stylesheet .= "$elm {";
		$stylesheet .= join( ' ', map( "$_:$style_ref->{$elm}{$_};", keys %{$style_ref->{$elm}} ) );
		$stylesheet .= '} ';
		$stylesheet .= "\n" if $self->{pretty};
	} # end foreach

	return $stylesheet;
} # end _write_stylesheet


############################################################
#
# Module: wadg::HTMLWriter::HTML_3_2
#
# Created: 16.May.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 2000,2001 Wadsack-Allen. All rights reserved.
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
# 2000.May.17 Added additional styles: width, border      JW
# 2000.May.18 Added style CLASS and ID support            JW
############################################################
package wadg::HTMLWriter::HTML_3_2;
use strict;

BEGIN {
	use vars       qw( $VERSION @ISA );
	$VERSION = do { my @r = (q$Revision: 2.00 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker
	@ISA         = qw( wadg::HTMLWriter );

} # end BEGIN
use vars      qw( $AUTOLOAD @EMPTY );
# This is the HTML 3.2 list of possibly EMPTY elements
@EMPTY = qw( BASEFONT BASE META LINK HR BR PARAM IMG AREA INPUT ISINDEX FRAME );

=back

=head1 HTML 3.2

HTMLWriter::HTML_3_2 - A HTML 3.2 compliant Writer class

=head1 DESCRIPTION

This class provides output for HTML 3.2 compliant markup. It 
understands STYLEs and will load a stylesheet (either through 
the C<-stylesheet> constructor option or through the C<style> 
method, below) and apply those styles to the output markup 
using HTML 3.2 compatible elements.

Currently, the style conversion understands the following styles:

 stlye               | default        | inherits?
 --------------------+----------------+-----------------
 background-color    | transparent    | only for elements with BGCOLOR attribute
 (background-image)  |                | no
 width               | auto           | no
 border-width        |                | no
 font-family         |                | yes
 font-size           |                | yes
 color               | auto*          | yes
 font-style          | normal         | yes (italic)
 font-weigth         | normal         | yes (bold)
 text-decoration     | none           | yes (underline, line-through, blink) 
 vertical-align      |                | yes (sub, super)
 text-align          |                | yes



=over 4

=cut

# ----------------------------------------------------------
# Sub: new
#
# Description: Contstruct a new HTMLWriter object with 
# HTML 3.2 settings.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub new {
	# Get constructor from parent
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $self = $class->SUPER::new( @_ );
   bless( $self, $class );
   
	# Get out own EMPTY elements list
   $self->{_EMPTY} = \@EMPTY;

	# Set default variables
   $self->{last_stylesheet} = [];
   
   return $self;
} # end new

# ----------------------------------------------------------
# Sub: AUTOLOAD
#
# Args: (Anything)
#
# Description: Just calls the _auto_tag of our SUPER
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub AUTOLOAD { 
	my $self = shift;
	my $name = $AUTOLOAD;
	   $name =~ s/.*://;
	return $self->_auto_tag( $name, @_ );
} # end AUTOLOAD

# ----------------------------------------------------------
# Sub: head
#
# Description: Just output like normal. Overrides -stylesheet
# insertion in parent.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May20 Created method                                JW
# ----------------------------------------------------------
sub head {
	my $self = shift;
	return $self->_auto_tag( 'head', @_ );
} # end head


# ----------------------------------------------------------
# Sub: end_head
#
# Description: Just output like normal. Overrides -stylesheet
# insertion in parent.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May20 Created method                                JW
# ----------------------------------------------------------
sub end_head {
	my $self = shift;
	return $self->_auto_tag( 'end_head' );
} # end end_head


=item doctype

Outputs the !DOCTYPE header for HTML 3.2 output like this:

 <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub doctype {
	my $self = shift;

	return '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2//EN">';
} # end doctype


=item style( %attr, $data )

Inserts a <STYLE> tag into the document as expected. This has the 
additonal benefit, in the HTML 3.2 version, of loading the contents, 
as specifed in $data into the internal stylesheet holder, so that 
they may be applied to later elements.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub style {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	# If the content is provided, use that
	$self->_parse_stylesheet( "@_" ) if @_;

	# If it's referenced through a SRC attribute, try to read the file
	if( defined $attrs{src} || defined $attrs{-src} ) {
		my $src = $attrs{src} || $attrs{-src};
		# Don't bother parsing absolute urls
		unless( $src =~ m#^\w://# ) {
			# Try to read the source file. May not work portably!
			if( $^O =~ /MacOS/ ) {
				$src =~ s#/#:#g;
				$src =~ s#^/##g;
			} # end if
			$self->_parse_stylesheet( $src ) if -f $src;
		} # end unless
	} # end if

	# Return nothing, cause this version doesn't support the style tag
	return '';
} # end style


=item body( \%attrs, @content )

Generates a body tag as expected. Also adjusts the LINK, VLINK, ALINK 
and TEXT attributes to match the psuedo-class styles a:*. if any.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub body {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	# NOTE: This won't do embedded body tags, which is good.
	return $self->start_body( \%attrs ) . join( '', @_ ) . $self->end_body();
} # end body



=item start_body( %\attrs )

Generates a opening body tag as expected. Adjusts the LINK, 
VLINK, ALINK and TEXT attributes to match the psuedo-class 
styles a:*. if any.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub start_body {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	if( defined $self->{_styles} ) {
		if( defined $self->{_styles}{body} && defined $self->{_styles}{body}{color} ) {
			$attrs{text} = $self->{_styles}{body}{color}; 
		} # end if
		if( defined $self->{_styles}{'a:visited'} && defined $self->{_styles}{'a:visited'}{color} ) {
			$attrs{vlink} = $self->{_styles}{'a:visited'}{color}; 
		} # end if
		if( defined $self->{_styles}{'a:active'} && defined $self->{_styles}{'a:active'}{color} ) {
			$attrs{alink} = $self->{_styles}{'a:active'}{color};
		} # end if
		if( defined $self->{_styles}{'a:link'} && defined $self->{_styles}{'a:link'}{color} ) {
			$attrs{link} = $self->{_styles}{'a:link'}{color};
		} # end if
	} # end if

	return $self->_auto_tag( 'start_body', \%attrs );
} # end start_body



=item span ( \%attrs, @content )

HTML 3.2 does not have a span, tag, yet this allows you to use
the <SPAN> tag to apply a class or element to the section. 

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Jun16 Created method                                JW
# ----------------------------------------------------------
sub span {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );
	my $res;
	
	my( $s, $e ) = $self->_convert_style( 'span', \%attrs );

	if( ref($_[0]) eq 'ARRAY' ) {
		# Do this whole thing for each element
		$res = join '', map( "$s$_$e", @{$_[0]} );
	} else {
		$res = $s . join( '', @_ ) . $e;
	} # end if

	return $res;
} # end span


=item start_span( %\attrs )

HTML 3.2 does not have a span, tag, yet this allows you to use
the <SPAN> tag to apply a class or element to the section. 

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub start_span {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	my( $s, $e ) = $self->_convert_style( 'span', \%attrs );
	return $s . $e;
} # end start_span


=item end_span()

HTML 3.2 does not have a span, tag, yet this allows you to use
the <SPAN> tag to apply a class or element to the section. 

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub end_span {
	my $self = shift;

	my( $s, $e ) = $self->_convert_style( 'span' );
	return $s.$e;
} # end end_span


# ----------------------------------------------------------
# Sub: _auto_tag
#
# Args: $name, @parms
#	$name	The name of the tag to generate
#	@parms	Any parms passed to the call
#
# This calls the SUPER to make the tag, but avoids adding 
# styles to EMPTY tags (elements that do not have content, like <BR>)
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _auto_tag {
	my $self = shift;
	my $name = shift;
	my $res = '';
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	# If this tag is empty, then don't do styles
	if( !@_ && 
		 ($name !~ /^start_/) &&
		 grep( /^$name$/i, @{$self->{_EMPTY}} ) ) {
		$self->{'-ignore-styles'}++;
	} # end if

	$res = $self->SUPER::_auto_tag( $name, \%attrs, @_ );

	# If this tag is empty, then restore style state
	if( !@_ && 
		 ($name !~ /^start_/) &&
		 grep( /^$name$/i, @{$self->{_EMPTY}} ) ) {
		$self->{'-ignore-styles'}--;
	} # end if

	return $res;
} # end _auto_tag

# ----------------------------------------------------------
# Sub: _make_tag
#
# Args: $tag, %attrs
#	$tag	The name of the element
#	$attrs	The reference to a hash of name value pairs for 
#	      	the attributes. For an opening tag, this is a 
#	      	hash or empty hash. For a closing tag this is not 
#	      	given (undef).
#
# Description: Internal method to create tags in the desired
# format. First, sets case to all CAPS, then calls the SUPER 
# to build up the tags, and finally calls _convert_styles to 
# apply style info, where defined.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _make_tag {
	my $self = shift;
	my( $tag, $attrs ) = @_;
	my $ret;

	# Set case of element
	$tag = uc($tag);
	
	if( (defined $attrs) && (ref($attrs) eq 'HASH') ) {
		# Set case of attribute names
		my %new_attrs;
		foreach ( keys %{$attrs} ) {
			$new_attrs{uc()} = $attrs->{$_};
		} # end foreach
		# Call super to build the tags, then converts the styles
		my( $s, $e ) = $self->_convert_style( $tag, \%new_attrs );
		$ret = $s . $self->SUPER::_make_tag( $tag, \%new_attrs ) . $e;
	} else {
		# Call super to build the tags, then converts the styles
		my( $s, $e ) = $self->_convert_style( $tag );
		$ret = $s . $self->SUPER::_make_tag( $tag ) . $e;
	} # end if

	return $ret;
} # end _make_tag


# ----------------------------------------------------------
# Sub: _convert_styles
#
# Args: $name, $attrs
#	$name 	The name of the tag to modify
#  $attrs	A hash ref for the tag's attributes
#
# Description: Converts styles in the current sheet to a 
# a set of prepend and append tags to return in the output.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May18 Added support for CLASS and ID as styles      JW
# 2000May18 Improved cascade through hash imports         JW
# 2000Jun16 Added support for CLASS and ID like td.total  JW
# 2000Jun16 Added support for background-image style      JW
# 2001Jan04 Moved alignment DIV outside elements          JW
#           Removed quotes in style values of fonts
# ----------------------------------------------------------
sub _convert_style {
	my $self = shift;
	my( $pre_start, $pre_end, $post_start, $post_end );
	my( $name, $attrs ) = @_;
	$name = lc( $name );

	# If this is an end-tag just pop off the style data
	unless( defined $attrs ) {
		my $list_ref = pop @{$self->{last_stylesheet}};
		($pre_end, $post_end) = @$list_ref if defined $list_ref;
		return ($pre_end, $post_end);
	} # end if
	
	# Apply styles to tags unless making style convertion tags
	unless( $self->{'-ignore-styles'} ) {

		#
		# Get the styles for this tag. Start with the context, then the 
		# element's style and the specific CLASS and ID for the tag
		#
		my %styles;
		my $s;
		foreach $s ( @{$self->{CONTEXT}} ) {
			map( $styles{$_} = $self->{_styles}{$s}{$_}, keys %{$self->{_styles}{$s}} ) if defined $self->{_styles}{$s};
		} # end foreach
		# Don't import background-color style unless element has a BGCOLOR attribute
		unless( grep /^$name$/i, qw( table tr th td tbody thead tfoot body ) ) {
			delete $styles{'background-color'};
		} # end unless
		# These properties don't inherit
		delete $styles{'width'};
		delete $styles{'border-width'};
		delete $styles{'background-image'};

		if( defined $self->{_styles}{$name} ) {
			map( $styles{$_} = $self->{_styles}{$name}{$_}, keys %{$self->{_styles}{$name}} );
		} # end if
		if( defined $attrs && defined $attrs->{CLASS} && defined $self->{_styles}{".$attrs->{CLASS}"} ) {
			map( $styles{$_} = $self->{_styles}{".$attrs->{CLASS}"}{$_}, keys %{$self->{_styles}{".$attrs->{CLASS}"}} );
		} # end if
		if( defined $attrs && defined $attrs->{ID} && defined $self->{_styles}{'#' . $attrs->{ID}} ) {
			map( $styles{$_} = $self->{_styles}{'#' . $attrs->{ID}}{$_}, keys %{$self->{_styles}{'#' . $attrs->{ID}}} );
		} # end if
		if( defined $attrs && defined $attrs->{CLASS} && defined $self->{_styles}{"$name.$attrs->{CLASS}"} ) {
			map( $styles{$_} = $self->{_styles}{"$name.$attrs->{CLASS}"}{$_}, keys %{$self->{_styles}{"$name.$attrs->{CLASS}"}} );
		} # end if
		if( defined $attrs && defined $attrs->{ID} && defined $self->{_styles}{"$name#" . $attrs->{ID}} ) {
			map( $styles{$_} = $self->{_styles}{"$name#" . $attrs->{ID}}{$_}, keys %{$self->{_styles}{"$name#" . $attrs->{ID}}} );
		} # end if

		if( %styles ) {
			# Set the ignore-styles setting so we don't convert ourselves
			$self->{'-ignore-styles'}++;

			#
			# Apply styles like background-color, width, and borders through a table wrapper
			#
			my %table;
			my %td;

			if( defined $styles{'background-color'} &&  $styles{'background-color'} !~ /^transparent$/i) {
				$td{bgcolor} = $styles{'background-color'};
			} # end if
			if( defined $styles{'background-image'} &&  $styles{'background-image'} !~ /^none$/i) {
				($table{background}) = $styles{'background-image'} =~ /url\s*\(\s*([^)]+?)\s*\)/;
			} # end if

			if( defined $styles{'width'} && $styles{'width'} !~ /^auto$/i ) {
				$table{width} = $styles{'width'};
				# -- Only us numbers (assume pixels) or percent
				$table{width} =~ s/([\d\%]+).*/$1/;
			} # end if

			if( defined $styles{'border-width'} && $styles{'border-width'} !~ /^$/i ) {
				$table{border} = $styles{'border-width'};
				# -- Just use the first decimal value given
				$table{border} =~ s/(\d+).*/$1/;
			} # end if

			if( keys %table || keys %td ) {
				# If it has a valid attribute set, then use that
				if( grep /^$name$/i, qw( table tr th td tbody thead tfoot body ) ) {
					if( defined $attrs ) {
						$attrs->{BGCOLOR} = $td{bgcolor} if defined $td{bgcolor};
						$attrs->{BACKGROUND} = $table{background} if defined $table{background};
						# If it has table attributes, then use those, otherwise skip these
						if( $name =~ /table/i ) {
							$attrs->{BORDER} = $table{border} if defined $table{border};
						} # end if
						if( grep /^$name$/i, qw( table tr th td tbody thead tfoot ) ) {
							$attrs->{WIDTH} = $table{width} if defined $table{width};
						} # end if
					} # end if
				} else {
					#  *** For inline-elements, this will convert to a block-element!
					$table{cellpadding} = 7 unless defined $table{cellpadding};
					$table{cellspacing} = 0 unless defined $table{cellspacing};
					$table{border}      = 0 unless defined $table{border};
					$pre_start = $self->start_table( \%table ) . $self->start_tr . $self->start_td( \%td ) . $pre_start;
					$post_end .= $self->end_td . $self->end_tr . $self->end_table;
				} # end if
			} # end if

			#
			# Apply font tags for font-face, font-size, and color. Estimate point size to size.
			#
			my %font;

			if( defined $styles{'font-family'} ) {
				$font{face} = $styles{'font-family'};
				# Remove any quotes in style values
				$font{face} =~ s/"//g;
			} # end if

			if( defined $styles{'font-size'} ) {
				my $i = 1;
				my( $pt ) = $styles{'font-size'} =~ /([\d\.]+)pt/;
				foreach (7, 8, 10, 13, 16, 20, 32) {
					 if( $pt <= $_ ) {
					 	$font{size} = $i;
					 	last;
					 } # end if
					 $i++;
				} # end for each
				# Remove any quotes in style values
				$font{size} =~ s/"//g;
			} # end if

			# -- This 'auto' overriding value is not a valid CSS value, but it's nice to 
			#    be able to override the colors for the <A> tag
			if( defined $styles{'color'} && $styles{color} !~ /^auto$/i) {
				$font{color} = $styles{'color'};
				# Remove any quotes in style values
				$font{color} =~ s/"//g;		#" For syntax highlighter
			} # end if

			# Insert the font tag unless it's a table or tr element.
			if( keys %font && !grep( /^$name$/i, qw( table tr ) ) ) {
				$post_start .= $self->start_font( \%font );
				$pre_end = $self->end_font() . $pre_end ;
			} # end if

			#
			# Apply italics, bold, underline, strike, blink, sub and super
			#
			if( $styles{'font-style'} =~ /italic/i ) {
				$post_start .= $self->start_i();
				$pre_end = $self->end_i() . $pre_end ;
			} # end if
			if( $styles{'font-weigth'} =~ /bold/i ) {
				$post_start .= $self->start_b();
				$pre_end = $self->end_b() . $pre_end ;
			} # end if
			if( $styles{'text-decoration'} =~ /underline/i ) {
				$post_start .= $self->start_u();
				$pre_end = $self->end_u() . $pre_end ;
			} # end if
			if( $styles{'text-decoration'} =~ /line-through/i ) {
				$post_start .= $self->start_strike();
				$pre_end = $self->end_strike() . $pre_end ;
			} # end if
			if( $styles{'text-decoration'} =~ /blink/ ) {
				$post_start .= $self->start_blink();
				$pre_end = $self->end_blink() . $pre_end ;
			} # end if
			if( $styles{'vertical-align'} =~ /sub/ ) {
				$post_start .= $self->start_sub();
				$pre_end = $self->end_sub() . $pre_end ;
			} # end if
			if( $styles{'vertical-align'} =~ /super/ ) {
				$post_start .= $self->start_super();
				$pre_end = $self->end_super() . $pre_end ;
			} # end if

			#
			# Apply alignment
			#
			if( defined $styles{'text-align'} ) {
				# If it has a valid attribute set, then use that
				if( grep /^$name$/i, qw( h1 h2 h3 h4 h5 h6 th td p hr table tr ) ) {
					if( defined $attrs ) {
						$attrs->{ALIGN} = uc($styles{'text-align'});
					} # end if
				} else {
					$pre_start .= $self->start_div( {align=>uc($styles{'text-align'})});
					$post_end = $self->end_div() . $pre_end ;
				} # end if
			} # end if

			# Reset the ignore-styles setting to continue processing
			$self->{'-ignore-styles'}--;
		} # end if

	} # end if

	if( defined $attrs ) {
		my $list_ref = [$pre_end, $post_end];
		push @{$self->{last_stylesheet}}, $list_ref;
		return ($pre_start, $post_start);
	} # end if

} # end _convert_style



############################################################
#
# Module: wadg::HTMLWriter::XHTML_1_0
#
# Created: 16.May.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 2000,2001 Wadsack-Allen. All rights reserved.
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
############################################################
package wadg::HTMLWriter::XHTML_1_0;
use strict;

BEGIN {
	use vars       qw( $VERSION @ISA );
	$VERSION = do { my @r = (q$Revision: 2.00 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker
	@ISA         = qw( wadg::HTMLWriter );
} # end BEGIN
use vars      qw( $AUTOLOAD @EMPTY );
@EMPTY = qw( BASE META LINK HR BR PARAM IMG AREA INPUT COL FRAME );

=back

=head1 XHTML

HTMLWriter::XHTML_1_0 - An XHTML 1.0 compliant Writer class

=head1 DESCRIPTION

This class provides output for XHTML 1.0 compliant markup. It 
converts all elements and attributes to lower case, makes sure 
all elements are closed or marked empty (as in <br />), quotes all 
attribute values, and provides values for boolean attributes. It
also forces inclusion of the <!DOCTYPE> elements, as required by 
XML and allows the inclusion of the <?xml?> processing instruction 
at the top of the file.

=over 4

=cut


# ----------------------------------------------------------
# Sub: new
#
# Description: Contstruct a new HTMLWriter object with 
# XHTML 1.0 settings.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub new {
	# Get constructor from parent
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $self = $class->SUPER::new( @_ );
   bless( $self, $class );
   
	# Get out own EMPTY elements list
   $self->{_EMPTY} = \@EMPTY;

	# Store a marker to say if doctype was written 
	$self->{_doctype} = 0;
	
   return $self;
} # end new


# ----------------------------------------------------------
# Sub: AUTOLOAD
#
# Args: (Anything)
#
# Description: Just calls the _auto_tag of our SUPER
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub AUTOLOAD { 
	my $self = shift;
	my $name = $AUTOLOAD;
	   $name =~ s/.*://;
	return $self->_auto_tag( $name, @_ );
} # end AUTOLOAD


=item doctype ( -flavor => 'Strict' )

Outputs the !DOCTYPE header for XHTML, something like this:

 <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN">

Where 'Strict', above, is defined by the named parameter 
'-flavor'. If none is given, 'Strict' is assumed. Valid 
flavors from the XHTML spec are 'Strict', 'Transitional,' 
and 'Frameset'.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 11Apr2001 Added system identifier for known flavors     JW
# 24Apr2001 Fixed warning about uninitialized flavor      JW
# ----------------------------------------------------------
sub doctype {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	# Set default flavor to 'Strict'
	unless( defined $attrs{flavor} || defined $attrs{-flavor} ) {
		$attrs{flavor} = 'Strict';
	} # end unless

	my $ret = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 ';
	$ret .= $attrs{flavor} || $attrs{-flavor};
	$ret .= '//EN" ';
	if( defined $attrs{flavor} ) {
		$ret .= ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"' if $attrs{flavor} eq 'Strict';
		$ret .= ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd"' if $attrs{flavor} eq 'Frameset';
		$ret .= ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"' if $attrs{flavor} eq 'Transitional';
	} # end if
	$ret .= '>';
	
	# We've done the doctype
	$self->{_doctype} = 1;

	return $ret;
} # end doctype


=item xml ( %named_attributes )

Outputs an XML header for XHTML, something like this:

 <?xml version="1.0" encoding="UTF-8"?>

The above 'version' and 'encoding' attributes are given 
by default. They can be overridden in the %named_attributes
provided.

B<NOTE:> This will only output before the DOCTYPE or HTML
has been written.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub xml {
	my $self = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	return '' if $self->{_doctype};

	# Set defaults
	unless( defined $attrs{version} || defined $attrs{-version} ) {
		$attrs{version} = '1.0';
	} # end unless
	unless( defined $attrs{encoding} || defined $attrs{-encoding} ) {
		$attrs{encoding} = 'UTF-8';
	} # end unless

	my $ret = $self->_make_tag( 'xml', \%attrs );
	$ret =~ s/^<([^>]+)>$/<\?$1\?>/;
	
	return $ret;
} # end xml


=item start_html (%attributes)

Outputs the starting <HTML> tag with the proper attributes. In 
order to comply with the XHMTL spec, this will include the 
C<xmlns> attribute if none is provided. This will also output 
the <DOCTYPE> if that hasn't been done yet.

=cut

# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub start_html {
	my $self = shift;
	my $name = shift;
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	# Set default xmlns if not set
	unless( defined $attrs{xmlns} || defined $attrs{-xmlns} ) {
		$attrs{xmlns} = 'http://www.w3.org/1999/xhtml';
	} # end unless

	my $res = $self->_make_tag( 'html', \%attrs );
	push @{$self->{CONTEXT}}, 'html';

	# If doctype hasn't been written then send it before HTML
	unless( $self->{_doctype} ) {
		$res = $self->doctype() . $res;
	} # end unless

	return $res;
} # end start_html


# ----------------------------------------------------------
# Sub: _auto_tag
#
# Args: $name, @parms
#	$name	The name of the tag to generate
#	@parms	Any parms passed to the call
#
# This calls the SUPER to make the tag, but adds the XML '/>'
# closure for EMPTY elements
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _auto_tag {
	my $self = shift;
	my $name = shift;
	my $res = '';
	my %attrs;
	%attrs = %{shift()} if( ref($_[0]) eq 'HASH' );

	$res = $self->SUPER::_auto_tag( $name, \%attrs, @_ );
	
	# If this tag is empty, then convert it to a 
	# backwards-compatible, XML-compliant style
	if( !@_ && 
		 ($name !~ /^start_/) &&
		 grep( /^$name$/i, @{$self->{_EMPTY}} ) ) {
		$res =~ s#>$# />#;
	} # end if

	return $res;
} # end _auto_tag

# ----------------------------------------------------------
# Sub: _make_tag
#
# Args: $tag, %attrs
#	$tag	The name of the element
#	$attrs	The reference to a hash of name value pairs for 
#	      	the attributes. For an opening tag, this is a 
#	      	hash or empty hash. For a closing tag this is not 
#	      	given (undef).
#
# Description: Internal method to create tags in the desired
# format. This just sets the case of all elements and 
# attributes and assures boolean attributes are fully compliant
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _make_tag {
	my $self = shift;
	my( $tag, $attrs ) = @_;
	my $ret = '';
	
	# Set case of element
	$tag = lc($tag);
	
	# Set case of attributes and fully form booleans
	if( (defined $attrs) && (ref($attrs) eq 'HASH') ) {
		my %new_attrs;
		foreach ( keys %{$attrs} ) {
			if( !defined($attrs->{$_}) || ($attrs->{$_} eq '') ) {
				$new_attrs{lc()} = $_;
			} else {
				$new_attrs{lc()} = $attrs->{$_};
			} #end if
		} # end foreach
		$ret = $self->SUPER::_make_tag( $tag, \%new_attrs );
	} else {
		$ret = $self->SUPER::_make_tag( $tag );
	} # end if

	return $ret;
} # end _make_tag


############################################################
# module clean-up code here (global destructor)
END { }


############################################################

=back

=head1 BUGS

=over 4

=item Cascading

Cascading only works partially. Because of the way Perl interprets lines like this,

	print $w->table( { border => 0, cellpadding => 6 },
	                 $w->tr( $w->td('User A:'), 
	                         $w->td( {-align=>'right'}, [ '2000', '1200', '1300' ] ), 
	                         $w->td( "kbps" ), 
	                       ),
	               );

there is no way for the HTMLWriter object to know, when rendering the <TD> elements, 
that they are in the context of the <TR> or <TABLE> element. There are two work-arounds
for this: 

(1) Explicitly specify the context in your style sheets (e.g. TD {} rather than 
TABLE {}). This is a good idea anyway because, not all user agents cascade equally. 
(Netscape's browsers don't cascade BODY into P or TD.) 

(2) Only use the C<start_> and C<end_> syntax in any containment and don't nest calls 
to HTML methods. In other words, write the above code like this, which is not as pretty:

	print $w->start_table( { border => 0, cellpadding => 6 } );
	print $w->start_tr();
	print $w->td('User A:');
	print $w->td( {-align=>'right'}, [ '2000', '1200', '1300' ] ), 
	print $w->td( "kbps" ), 
	print $w->end_tr();
	print $w->end_table();

=item Stylsheet parsing

The parser used in the HTML 3.2 syntax converter is very simple. It expects one selector
per group (e.g. H1 { color:green } not H1,H2 {color:green}) and only understands explicit
elements, class and id names as selectors. It also only interprets a small handful of all the 
valid CSS styles. 

The parser will load embedded style sheets (in <STYLE>...</STYLE> elements) and will try 
to load I<locally hosted> external style sheets (in <STYLE SRC="..."></STYLE> elements). 
It will ignore C<@import> rules and inline styles (in the STYLE attribute of an HTML 
element). It will also ignore any non-css style sheets.

=item CGI

This has not been tested under mod_perl, PerlEx or any other standard or 
non-standard CGI interfaces.


=item Redundancy

Yes, this kind of functionality is provided by things like C<CGI>, C<HTML::AsSubs>, 
C<HTML::Formatter>, etc. but not in a way that works well here. C<HTML::AsSubs> is not 
an OO interface and C<CGI> cannot easily be subclassed (though it could be delegated). 
The C<HTML::Formatter>s would require the whole overhead of the parser and element tree 
classes and cannot be streamed, unbuffered, to the output. So this works, for our needs 
in the space between those libraries.

Perhaps these could all be coalleced into one HTML writing / building library that works 
for all situations. Especially if that tool could be assocaited with DTDs and properly 
manage systax checking, tree building, etc. as well as providing the forward-looking, 
backwards-compatability rendering offered by the HTML 3.2 version of this class. :)

=back

=head1 VERSION

2.00

=head1 AUTHOR

Jeremy Wadsack for Wadsack-Allen Digital Group (dgsupport@wadsack-allen.com)

=head1 COPYRIGHT

Copyright (C) 2000,2001 Wadsack-Allen. All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;  # so the require or use succeeds
