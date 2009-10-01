package Maypole::PSGI;

use strict;
use 5.008_001;
our $VERSION = '0.01';

use UNIVERSAL::require;

sub new {
    my($class, $module) = @_;

    $module->require or die "Couldn't load $module: $@";

    # Horrible HACK: Maypole::Application doesn't allow me to hook
    # which class to inherit from: Change that here.
    no strict 'refs';
    for (@{"$module\::ISA"}) {
        $_ = "Maypole::PSGI::Application" if $_ eq 'CGI::Maypole';
    }

    bless { module => $module }, $class;
}

sub run {
    my($self, $env) = @_;
    $self->{module}->run_psgi($env);
}

package Maypole::PSGI::Application;
use base qw( CGI::Maypole );

use CGI::PSGI;
use Maypole::Constants;

sub get_request {
    my($self, $env) = @_;
    $self->cgi(CGI::PSGI->new($env));
}

sub run_psgi {
    my $class = shift;
    my($status, $res) = $class->handler(@_);

    if ($status != OK) {
        return [ 500, [ 'Content-Type' => 'text/html' ], [ 'Maypole Application Error' ] ];
    }

    return $res;
}

# Maypole doesn't allow me to get headers and content separately.
# HTTPD::Frontend's way to use package vars is not thread/event-loop safe
# So, just copy that :/
sub handler : method  {
    my ($class, $req) = @_;
    $class->init unless $class->init_done;

    my $self = $class->new;

    # initialise the request
    $self->headers_out(Maypole::Headers->new);
    $self->get_request($req);

    $self->parse_location;

    # hook useful for declining static requests e.g. images, or perhaps for
    # sanitizing request parameters
    $self->status(Maypole::Constants::OK());
    # set the default
    $self->__call_hook('start_request_hook');
    return $self->status unless $self->status == Maypole::Constants::OK();
    die "status undefined after start_request_hook()" unless defined
        $self->status;

    my $session = $self->get_session;
    $self->session($self->{session} || $session);
    my $user = $self->get_user;
    $self->user($self->{user} || $user);

    my $status = $self->handler_guts;
    return $status unless $status == OK;

    # copied from collect_output()
    my %headers = (
        -type            => $self->content_type,
        -charset         => $self->document_encoding,
        -content_length  => do { use bytes;
                                 length $self->output },
    );

    foreach ($self->headers_out->field_names) {
        next if /^Content-(Type|Length)/;
        $headers{"-$_"} = $self->headers_out->get($_);
    }

    return $status, [ $self->cgi->psgi_header(%headers), [ $self->output ] ];
}

package Maypole::PSGI;

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Maypole::PSGI - Runs Maypole application as PSGI application

=head1 SYNOPSIS

  # in app.psgi
  use BeerDB;
  use Maypole::PSGI;

  my $app = Maypole::PSGI->new('BeerDB');
  my $handler = sub { $app->run(@_) };

=head1 DESCRIPTION

Maypole::PSGI is an Maypole adapter to run Maypole application on any
PSGI server. It uses L<CGI::PSGI> and then wrap CGI::Maypole and does
some really wacky hack to adapt Maypole's hardcoded dispatcher list,
but it works :)

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Maypole> L<CGI::PSGI>

=cut
