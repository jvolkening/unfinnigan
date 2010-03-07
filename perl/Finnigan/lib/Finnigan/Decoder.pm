package Finnigan::Decoder;

use 5.010000;
use strict;
use warnings;

our $VERSION = '0.01';

sub windows_datetime_in_bytes {
  # expects 8 arguments representing windows date in little-endian order

  require DateTime::Format::WindowsFileTime;

  my @hex = map { sprintf "%2.2X", $_ } @_; # convert to upper-case hex
  my $hex_date = join('', @hex[reverse 0..7]); # swap to network format
  my $dt = DateTime::Format::WindowsFileTime->parse_datetime( $hex_date );
  # $dt is a regular DateTime object
  return $dt->ymd . " " . $dt->hms;
}

sub read {
  my ($class, $stream, $fields) = @_;
  my $self = {};
  my ( $rec, $nbytes );  

  bless $self, $class;

  my $addr = my $current_addr = tell $stream;
  my $size = 0;

  foreach my $i ( 0 .. @$fields/2 - 1 ) {
    my ($name, $template) = ($fields->[2*$i], $fields->[2*$i+1]);
    my $value;

    die qq(key "$name" already exists) if $self->item($name);

    if ( $template =~ /^object=/ ) {
      my $class = (split /=/, $template)[-1];
      $value = eval{$class}->decode($stream);
      $nbytes = $value->size();
    }
    elsif ( $template eq 'windows_time' ) {
      my $bytes_to_read = 8;
      $nbytes = read $stream, $rec, 8;
      $nbytes == $bytes_to_read
	or die "could not read all $bytes_to_read bytes of $name at $current_addr";
      $value = windows_datetime_in_bytes(unpack "W*", $rec);
    }
    else {
      my $bytes_to_read = length(pack($template,()));
      $nbytes = read $stream, $rec, $bytes_to_read;
      $nbytes == $bytes_to_read
	or die "could not read all $bytes_to_read bytes of $name at $current_addr";

      if ($template =~ /^U0C/) {
	$value = pack "C*", unpack $template, $rec;
      }
      else {
	$value = unpack $template, $rec;
      }
    }

    $self->{data}->{$name} = {
			      seq => $i,
			      addr => $current_addr,
			      size => $nbytes,
			      value => $value
			     };
    $current_addr = tell $stream;
    $size += $nbytes;
  }

  $self->{addr} = $addr;
  $self->{size} = $size;

  return $self;
}

sub size {
  shift->{size};
}

sub data {
  shift->{data};
}

sub item {
  my ($self, $key) = @_;
  $self->{data}->{$key};
}

sub dump {
  my ( $self ) = @_;
  my @keys = sort {
    $self->data->{$a}->{seq} <=> $self->data->{$b}->{seq}
  } keys %{$self->{data}};
  foreach my $key ( @keys ) {
    my $value = $self->item($key)->{value};
    say join("\t",
	     $self->item($key)->{addr},
	     $self->item($key)->{size},
	     $key,
	     ref($value) ? ref($value) : $value,
	    );
  }
}

1;
__END__
=head1 NAME

Finnigan::Decoder - a generic binary structure decoder

=head1 SYNOPSIS

  use Finnigan;

  my $fields = [
		short_int => 'v',
		long_int => 'V',
		ascii_string => 'C60',
		wide_string => 'U0C18',
		audit_tag => 'object=Finnigan::AuditTag',
		time => 'windows_time',
	       ];

  my $data = Finnigan::Decoder->read(\*STREAM, $fields);


=head1 DESCRIPTION

This class is not inteded to be used directly; it is a parent class
for all Finnigan decoders. The fields to decode are passed to
the decoder's read() method in a list reference, where every even item
specifies the key the item will be known as in the resulting hash, and
every odd item specifies the unpack template.

The templates starting with 'object=' instruct the current decoder to
call another Finnigan decoder at that location. A special template
'windows_time' instructs the current decoders parent class,
Finingan::Decoder, to call its own Windows timestamp routine.

=head2 EXPORT

None


=head1 SEE ALSO

Use this command to list all available Finnigan decoders:

 perl -MFinnigan -e 'Finnigan::list_modules'


=head1 AUTHOR

Gene Selkov, E<lt>selkovjr@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Gene Selkov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
