package MojoX::Tusu::Component::MailFormExample;
use strict;
use warnings;
use utf8;
use base qw(MojoX::Tusu::Component::MailFormBase);
use Fcntl qw(:flock);
    
    sub init {
        my ($self, $app) = @_;
        $self->set_ini({
            'tmp_dir'           => '',
            'mailto'            => [],
            'logfile'           => $app->home->rel_file(__PACKAGE__),
            'smtp_from'         => 'noreply', ## you can fill @host if needed
            'smtp_server'       => 'localhost',
            'form_elements'     => [qw{name mail pref addr company tel1 tel2 tel3 etc}],
            'auto_respond_to'   => 'mail',
            'upload' => {
                allowed_extention => ['doc','xls','txt','pdf'],
                max_filesize => 100000,
            }
        });
    }

    sub validate_form {
        
        my ($self) = @_;
        my $c = $self->controller;
        my $formdata = $c->req->body_params;
        my $user_err = $self->user_err;
        
        for my $key ('tel1','tel2','tel3') {
            if (! $formdata->param($key)) {
                $user_err->stack('お電話番号は必須項目です');
                last;
            }
        }
        
        if (my $mail = $formdata->param('mail')) {
            $mail =~ tr/Ａ-Ｚａ-ｚ０-９/A-Za-z0-9/;
            if ($mail !~ /^[^@]+@[^.]+\..+/){
                $user_err->stack('メールアドレスが正しくありません');
            }
        }
        if ($formdata->param('etc') && length($formdata->param('etc')) > 10000) {
            $user_err->stack('お問い合わせ内容がサイズの上限を超えました');
        }
    }
    
    sub mail_attr {
        
        my ($self) = @_;
        my $c = $self->controller;
        
        my $tpl = Text::PSTemplate->new;
        for my $key (@{$self->ini('form_elements')}) {
            $tpl->set_var($key => $c->req->body_params->param($key));
        }
        my $subject = 'Someone send inquiry';
        
        my $body = $tpl->parse(<<'EOF');
Thank you for Consider our product.

【】
-----------------------------------------------
[住所]
  <% $addr %>

[担当者名]
  <% $rep %>

[メールアドレス]
  <% $mail %>

[電話]
  <% $tel1 %>-<% $tel2 %>-<% $tel3 %>

[FAX]
  <% $fax1 %>-<% $fax2 %>-<% $fax3 %>

[備考欄]
<% $etc %>
-----------------------------------------------
EOF
        $body = $self->jp_char_normalize($body);
        return $subject, $body;
    }
    
    sub mail_attr_respond {
        
        my ($self) = @_;
        
        my $c = $self->controller;
        my $tpl = Text::PSTemplate->new;
        for my $key (@{$self->ini('form_elements')}) {
            $tpl->set_var($key => $c->req->body_params->param($key));
        }
        my $subject = 'Thank you';
        
        my $body = $tpl->parse(<<'EOF');
<% $rep %> 様

Thank you

【】
-----------------------------------------------
[住所]
  <% $addr %>

[担当者名]
  <% $rep %>

[メールアドレス]
  <% $mail %>

[電話]
  <% $tel1 %>-<% $tel2 %>-<% $tel3 %>

[FAX]
  <% $fax1 %>-<% $fax2 %>-<% $fax3 %>

[備考欄]
<% $etc %>
-----------------------------------------------

上記の内容で間違いがないか必ずご確認ください。
万一、お申込みに覚えがない場合や、記載内容に間違いがある場合は、
ご面倒ですが下記までご連絡ください。

◆◇………………………………………………
test@example.com
………………………………………………◇◆
EOF

        $body = $self->jp_char_normalize($body);
        
        return $subject, $body;
    }
    
    sub jp_char_normalize {
        
        my ($self, $in) = @_;
        $in =~ tr/[\x{ff5e}\x{2225}\x{ff0d}\x{ffe0}\x{ffe1}\x{ffe2}]/[\x{301c}\x{2016}\x{2212}\x{00a2}\x{00a3}\x{00ac}]/;
        return $in;
    }

1;

__END__

=head1 NAME

MojoX::Tusu::Component::MailFormExample

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
