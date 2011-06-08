package MojoX::Tusu::Component::MailFormBase;
use strict;
use warnings;
use utf8;
use base qw(MojoX::Tusu::ComponentBase);
use Encode;
use Net::SMTP;
use MIME::Entity;
use Fcntl qw(:flock);
use Carp;

	sub get {
		
		my ($self, $c) = @_;
		$self->validate_form($c);
		$self->save_temporary_file($c);
		my $template;
		if ($self->user_err->count) {
			$template = $c->req->body_params->param('errorpage');
		} else {
			$template = $c->req->body_params->param('nextpage');
		}
		$c->render(handler => 'tusu', template => $template);
	}
	
	sub post {
		
		my ($self, $c) = @_;
		
		use Mojolicious::Sessions;
        if (! $c->session(__PACKAGE__. '::session_id')) {
            $c->session(__PACKAGE__. '::session_id' => session_id());
        }
		
		if (! $c->req->body_params->param('send')) {
			return $self->get($c);
		}
		
		$self->validate_form($c);
		
		my $template;
		if ($self->user_err->count) {
			$template = $c->req->body_params->param('errorpage');
		} else {
			$self->sendmail;
			$template = $c->req->body_params->param('nextpage');
		}
		$c->render(handler => 'tusu', template => $template);
	}
	
	sub save_temporary_file {
		
		my ($self, $c) = @_;
		my @files = $c->req->upload('file');
		foreach my $file (@files) {
			my $name = $c->session(__PACKAGE__. '::session_id'). '_file_'. $file->filename;
			my $tmp_name = File::Spec->catfile($self->ini('upload')->{dir}, $name);
			$file->move_to($tmp_name);
		}
	}
	
	sub validate_form {
		croak 'It must be implemented by sub classes';
	}
	
	sub sendmail_forward {
		my ($self) = @_;
		my $c = $self->controller;
		my $body = '';
		for my $key (@{$self->ini('form_elements')}) {
			$body .= sprintf("[%s]\n%s\n", $key, $c->req->body_params->param($key));
		}
		return 'Thank you for sending', $body;
	}
	
	sub sendmail_auto_respond {
		my ($self) = @_;
		my $c = $self->controller;
		my $body = '';
		for my $key (@{$self->ini('form_elements')}) {
			$body .= sprintf("[%s]\n%s\n", $key, $c->req->body_params->param($key));
		}
		return 'Thank you for sending', $body;
	}
	
	sub sendmail {
		
		my ($self) = @_;
		my $c = $self->controller;
		my $mailto = $self->ini('mailto');
		my $auto_respond_to = $c->req->body_params->param($self->ini('auto_respond_to'));
		
		my @attach = ();
		if ($self->ini('upload')) {
			opendir(my $dir, $self->ini('upload')->{dir});
			my $filename_base = $c->session(__PACKAGE__. '::session_id');
			my @files = grep {
				$_ =~ /^$filename_base\_/
				&& -f File::Spec->catfile($self->ini('upload')->{dir}, $_), 
			} readdir($dir);
			close($dir);
			foreach my $file (@files) {
				push(@attach, $self->ini('upload')->{dir}. "/". $file);
			}
		}
		
		my @mail_attr = $self->mail_attr;
		$self->sendmail_backend($mailto, @mail_attr, \@attach);
		$self->sendmail_backend($auto_respond_to, $self->mail_attr_respond);
		
		$self->write_log($mail_attr[1]);
		
		foreach my $file (@attach) {
			unlink $file;
		}
	}
	
	sub mail_attr {
		croak 'It must be implemented by sub classes';
	}
	
	sub mail_attr_respond {
		croak 'It must be implemented by sub classes';
	}
	
	sub sendmail_backend {
		
		my ($self, $to, $subject, $body, $attach) = @_;
		my $c = $self->controller;
		
		utf8::encode($subject);
		Encode::from_to($subject, 'utf8', 'iso-2022-jp');
		utf8::encode($body);
		Encode::from_to($body, 'utf8', 'iso-2022-jp');
		
		$to = (ref $to) ? $to : [$to];
		
		for my $addr (@$to) {
			my $smtp = Net::SMTP->new($self->ini('smtp_server'));
			my $smtp_from = $self->ini('smtp_from');
			if ($smtp_from !~ /\@/) {
				$smtp_from .= '@'. $c->req->url->to_abs->host;
			}
			$smtp->mail($smtp_from);
			$smtp->to($addr);
			
			my $mime = MIME::Entity->build(
				To      => $addr,
				Subject => $subject,
				Data    => [$body],
			);
			foreach my $name (@$attach) {
				my $send_name = $name;
				$send_name =~ s{^.+?_.+?_}{};
				$mime->attach(
					Filename => $send_name,
					Path     => $name,
					Type     => 'application/octet-stream',
					Encoding => 'Base64'
				);
			}
			$smtp->data();
			$smtp->datasend($mime->stringify);
			$smtp->datasend();
			$smtp->quit();
		}
	}
	
	sub put_all_elems_in_hidden : TplExport {

		my ($self) = @_;
		my $c = $self->controller;
		my $out = '';
		for my $key (@{$self->ini('form_elements')}) {
			my $val = $c->req->body_params->param($key) || '';
			$out .= sprintf(qq{<input type="hidden" name="%s" value="%s" />}, $key, $val);
		}
		return $out;
	}
	
	sub put_user_err : TplExport {
		
		my ($self, $id) = @_;
		my $c = $self->controller;
		if ($self->user_err->count) {
			$id ||= 'error';
			my @errs = map {'<li>'. $_. '</li>'} $self->user_err->array;
			return '<ul id="'. $id. '">'. join('', @errs). '</ul>';
		}
		return;
	}
	
	sub write_log {
		
		my ($self, $body) = @_;
		if (my $file = $self->ini('logfile')) {
			my $time = localtime(time());
			open(my $fh, ">>:utf8", $file) || warn "$file cannot open\n";
			if ($fh and flock($fh, LOCK_EX)) {
				print $fh "=======================================================";
				print $fh "\nDate: $time";
				print $fh "\n";
				print $fh "\n$body";
				print $fh "\n";
			}
			close $fh;
			chmod(0777, $file);
		}
	}
	
	### --------------
	### generate session id
	### --------------
	sub session_id {
		
		use Digest::SHA;
		return Digest::SHA::sha512_hex($^T. $$. rand(1000000));
	}
	
	sub mail_id {
		
		my ($self, $addr, $body) = @_;
		use Digest::SHA;
		return Digest::SHA::sha1($^T. $body);
	}
	
	sub user_err {
		
		my ($self) = @_;
		my $c = $self->controller;
		if (! $c->stash('user_err')) {
			$c->stash('user_err', _Use_error->new)
		}
		return $c->stash('user_err');
	}

package _Use_error;
use strict;
use warnings;

	sub new {
		return bless [], shift;
	}
	
	sub stack {
		my ($self, $err) = @_;
		push(@$self, $err);
		return $self;
	}
	
	sub count {
		my ($self) = @_;
		return scalar @$self;
	}
	
	sub array {
		my ($self) = @_;
		return @$self;
	}

1;

__END__

=head1 NAME

MojoX::Tusu::Component::MailFormBase

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 TEMPLATE FUNCTIONS

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
