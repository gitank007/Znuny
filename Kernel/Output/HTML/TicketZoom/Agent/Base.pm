# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::TicketZoom::Agent::Base;

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);

use Kernel::System::VariableCheck qw(IsHashRefWithData);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Log',
    'Kernel::System::SystemAddress',
    'Kernel::System::Ticket::Article',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 ArticleRender()

Returns article html.

    my $HTML = $ArticleBaseObject->ArticleRender(
        TicketID                    => 123,         # (required)
        ArticleID                   => 123,         # (required)
        UserID                      => 123,         # (required)
        ShowBrowserLinkMessage      => 1,           # (optional) Default: 0.
        ArticleActions              => [],          # (optional)
    );

Result:
    $HTML = "<div>...</div>";

=cut

sub ArticleRender {
    ...;    ## no critic
}

=head2 ArticleMetaFields()

Returns common fields for any article.

    my %ArticleMetaFields = $ArticleBaseObject->ArticleMetaFields(
        TicketID  => 123,   # (required)
        ArticleID => 123,   # (required)
        UserID    => 123,   # (required)
    );

Returns:

    %ArticleMetaFields = (
        DynamicField_Item => {
            Label => 'Item',            # mandatory
            Value => 'Value',           # mandatory
            Link => 'http://...',       # optional
        },
        AccountedTime => {
            ...
        },
    );

=cut

sub ArticleMetaFields {
    my ( $Self, %Param ) = @_;

    # Check needed stuff.
    for my $Needed (qw(TicketID ArticleID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
    my $LayoutObject  = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my %Result;

    # show accounted article time
    if (
        $ConfigObject->Get('Ticket::ZoomTimeDisplay')
        && $ConfigObject->Get('Ticket::Frontend::AccountTime')
        )
    {
        my $ArticleTime = $ArticleObject->ArticleAccountedTimeGet(
            ArticleID => $Param{ArticleID},
        );
        if ($ArticleTime) {
            $Result{Time} = {
                Label => "Time",
                Value => $ArticleTime,
            };
        }
    }

    # get dynamic field config for frontend module
    my $DynamicFieldFilter = {
        %{ $ConfigObject->Get("Ticket::Frontend::AgentTicketZoom")->{DynamicField} || {} },
        %{
            $ConfigObject->Get("Ticket::Frontend::AgentTicketZoom")->{ProcessWidgetDynamicField}
                || {}
        },
    };

    # get the dynamic fields for article object
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => ['Article'],
        FieldFilter => $DynamicFieldFilter || {},
    );
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # cycle trough the activated Dynamic Fields
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        my $Value = $DynamicFieldBackendObject->ValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID           => $Param{ArticleID},
        );

        next DYNAMICFIELD if !$Value;
        next DYNAMICFIELD if $Value eq '';

        # get print string for this dynamic field
        my $ValueStrg = $DynamicFieldBackendObject->DisplayValueRender(
            DynamicFieldConfig => $DynamicFieldConfig,
            Value              => $Value,
            ValueMaxChars      => $ConfigObject->Get('Ticket::Frontend::DynamicFieldsZoomMaxSizeArticle')
                || 160,    # limit for article display
            LayoutObject => $LayoutObject,
        );

        my $Label = $DynamicFieldConfig->{Label};

        $Result{ $DynamicFieldConfig->{Name} } = {
            Label => $Label,
            Value => $ValueStrg->{Value},
            Title => $ValueStrg->{Title},
        };

        if ( $ValueStrg->{Link} ) {
            $Result{ $DynamicFieldConfig->{Name} }->{Link} = $ValueStrg->{Link};
        }
    }

    return %Result;
}

=head1 PRIVATE FUNCTIONS

=head2 _ArticleSenderImage()

Get URL used for article sender image.

    my $SenderImage = $ArticleBaseObject->_ArticleSenderImage(
        Sender => 'John Doe <jdoe@example.com>',
    );

Returns:

    $SenderImage = 'https://gravatar.com/avatar/28a58af1db24962e81212115e7cac685?s=80';

=cut

sub _ArticleSenderImage {
    my ( $Self, %Param ) = @_;

    my $Result = '';

    return $Result if !$Param{Sender};

    my $Size = 80;

    # Get email address from sender field.
    my $EmailParser = Kernel::System::EmailParser->new(
        %{$Self},
        Mode => 'Standalone',
    );
    my @Addresses = $EmailParser->SplitAddressLine( Line => $Param{Sender} );
    if (@Addresses) {
        my $Email = $EmailParser->GetEmailAddress( Email => $Addresses[0] );
        if ($Email) {
            my $IsLocal = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressIsLocalAddress(
                Address => $Email,
            );
            if ( !$IsLocal ) {
                $Result = 'https://www.gravatar.com/avatar/' . md5_hex( lc $Email ) . '?s=' . $Size . '&d=identicon';
            }
        }
    }

    return $Result;
}

=head2 _ArticleSenderInitials()

Get sender initials.

    my $SenderInitials = $ArticleBaseObject->_ArticleSenderInitials(
        Sender => 'John Doe',
    );

Returns:

    $SenderInitials = 'JD';

=cut

sub _ArticleSenderInitials {
    my ( $Self, %Param ) = @_;

    my $SenderInitials = 'O';

    return $SenderInitials if !$Param{Sender};

    # Split sender name by whitespace.
    my @Sender = split /\s+/, $Param{Sender};
    if (@Sender) {
        $SenderInitials = uc substr $Sender[0], 0, 1;
        if ( @Sender > 1 ) {
            $SenderInitials .= uc substr $Sender[-1], 0, 1;
        }
    }

    return $SenderInitials;
}

sub _ArticleModuleMeta {
    my ( $Self, %Param ) = @_;

    # Check needed stuff.
    for my $Needed (qw(TicketID ArticleID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check whether auto article links should be used
    return if !$ConfigObject->Get('Ticket::Frontend::ZoomCollectMeta');
    return if !$ConfigObject->Get('Ticket::Frontend::ZoomCollectMetaFilters');

    my $ArticlePlain = $LayoutObject->ArticlePreview(
        %Param,
        ResultType => 'plain',
    );

    my @Data;

    # find words to replace
    my %Config = %{ $ConfigObject->Get('Ticket::Frontend::ZoomCollectMetaFilters') };

    FILTER:
    for my $Filter ( values %Config ) {

        my %FilterData;

        # check for needed data
        next FILTER if !$Filter->{RegExp};
        next FILTER if !$Filter->{Meta};
        next FILTER if !$Filter->{Meta}->{Name};
        next FILTER if !$Filter->{Meta}->{URL};

        # iterage through regular expressions and create a hash with found matches
        my @Matches;
        for my $RegExp ( @{ $Filter->{RegExp} } ) {

            my @Count    = $RegExp =~ m{\(}gx;
            my $Elements = scalar @Count;

            if ( my @MatchData = $ArticlePlain =~ m{([\s:]$RegExp)}gxi ) {
                my $Counter = 0;

                MATCH:
                while ( $MatchData[$Counter] ) {

                    my $WholeMatchString = $MatchData[$Counter];
                    $WholeMatchString =~ s/^\s+|\s+$//g;
                    if ( grep { $_->{Name} eq $WholeMatchString } @Matches ) {
                        $Counter += $Elements + 1;
                        next MATCH;
                    }

                    my %Parts;
                    for ( 1 .. $Elements ) {
                        $Parts{$_} = $MatchData[ $Counter + $_ ];
                    }
                    $Counter += $Elements + 1;

                    push @Matches, {
                        Name  => $WholeMatchString,
                        Parts => \%Parts,
                    };
                }
            }
        }

        if ( scalar @Matches ) {

            $FilterData{Name} = $Filter->{Meta}->{Name};

            # iterate trough matches and build URLs from configuration
            for my $Match (@Matches) {

                my $MatchQuote = $LayoutObject->Ascii2Html( Text => $Match->{Name} );
                my $URL        = $Filter->{Meta}->{URL};
                my $URLPreview = $Filter->{Meta}->{URLPreview};

                # replace the whole keyword
                my $MatchLinkEncode = $LayoutObject->LinkEncode( $Match->{Name} );
                $URL =~ s/<MATCH>/$MatchLinkEncode/g;
                $URLPreview =~ s/<MATCH>/$MatchLinkEncode/g;

                # replace the keyword components
                for my $Part ( sort keys %{ $Match->{Parts} || {} } ) {
                    $MatchLinkEncode = $LayoutObject->LinkEncode( $Match->{Parts}->{$Part} );
                    $URL =~ s/<MATCH$Part>/$MatchLinkEncode/g;
                    $URLPreview =~ s/<MATCH$Part>/$MatchLinkEncode/g;
                }

                push @{ $FilterData{Matches} }, {
                    Text       => $Match->{Name},
                    URL        => $URL,
                    URLPreview => $URLPreview,
                    Target     => $Filter->{Meta}->{Target} || '_blank',
                };
            }
            push @Data, \%FilterData;
        }
    }

    return @Data;
}

1;
