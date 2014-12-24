package Developer::Listing;
use strict;
use warnings;

sub _mtmljob_tagkind_options {
    my $component = MT->component( 'Developer' );
    return [
    {   label => $component->translate( 'Function Tag' ),
        text  => 'Function Tag',
        value => 'function',
    },
    {   label => $component->translate( 'Block Tag' ),
        text  => 'Block Tag',
        value => 'block',
    },
    {   label => $component->translate( 'Conditional Tag' ),
        text  => 'Conditional Tag',
        value => 'conditonal',
    },
    {   label => $component->translate( 'Global Modifier' ),
        text  => 'Global Modifier',
        value => 'modifier',
    },
]
}

sub _mtmljob_trigger_options {
    my $component = MT->component( 'Developer' );
    return [
    {   label => $component->translate( 'None' ),
        text  => 'None',
        value => 0,
    },
    {   label => $component->translate( 'Every time' ),
        text  => 'Every time',
        value => 1,
    },
    {   label => $component->translate( 'One time' ),
        text  => 'One time',
        value => 2,
    },
    {   label => $component->translate( 'Hourly' ),
        text  => 'Hourly',
        value => 3,
    },
    {   label => $component->translate( 'Daily' ),
        text  => 'Daily',
        value => 4,
    },
    {   label => $component->translate( 'Weekly' ),
        text  => 'Weekly',
        value => 5,
    },
    {   label => $component->translate( 'Monthly' ),
        text  => 'Monthly',
        value => 6,
    },
    {   label => $component->translate( 'Callback' ),
        text  => 'Callback',
        value => 7,
    },
    {   label => $component->translate( 'MT Tag' ),
        text  => 'MT Tag',
        value => 8,
    },
    {   label => $component->translate( 'Application' ),
        text  => 'Application',
        value => 9,
    },
    {   label => $component->translate( 'Method' ),
        text  => 'Method',
        value => 10,
    },
    {   label => $component->translate( 'Data API Endpoint' ),
        text  => 'Data API',
        value => 11,
    },
    {   label => 'config.yaml',
        text  => 'config.yaml',
        value => 12,
    },
]
}

sub _content_actions {
    my $component = MT->component( 'Developer' );
    my $actions = {
        create_alttemplate => {
            label => 'Create New',
            mode  => 'edit',
            class => 'icon-create',
            args  => { _type => 'alttemplate' },
            order => 300,
        },
        # install_login_template => {
        #     label => 'Install Member Site\'s Templates',
        #     mode  => 'install_sign_in_template',
        #     class => 'icon-create',
        #     order => 400,
        #     confirm_msg => $component->translate( 'Are you sure you want to install member site\'s alternative templates?' ),
        #     condition => sub { return MT->config( 'DeveloperRegistration' ) }
        # },
    };
    return $actions;
}

sub _list_actions {
    my $component = MT->component( 'Developer' );
    my $actions = {
        delete => {
            button      => 1,
            label       => 'Delete',
            mode        => 'delete',
            class       => 'icon-action',
            return_args => 1,
            args        => { _type => 'mtmljob' },
            order       => 300,
        },
        enable_jobs => {
            button      => 1,
            label       => 'Enabled',
            mode        => 'change_status_jobs',
            class       => 'icon-action',
            return_args => 1,
            order       => 400,
        },
        disable_jobs => {
            button      => 1,
            label       => 'Disabled',
            mode        => 'change_status_jobs',
            return_args => 1,
            order       => 500,
        },
        export_jobs => {
            button      => 0,
            label       => 'Export Plugin',
            mode        => 'mtmljobs_to_plugin',
            return_args => 1,
            order       => 600,
            input       => 1,
            input_label => $component->translate( 'Enter a Plugin Name' ),
        },
    };
    return $actions;
}

sub _list_actions_log {
    my $actions = {
        delete => {
            button      => 1,
            label       => 'Delete',
            mode        => 'delete',
            class       => 'icon-action',
            return_args => 1,
            args        => { _type => 'log' },
            order       => 300,
            condition   => sub { 
                return 1 if MT->instance->user and MT->instance->user->is_superuser;
                return undef; },
        },
        # download_log => {
        #     button      => 1,
        #     label       => 'Export',
        #     mode        => '_export_system_log',
        #     class       => 'icon-action',
        #     return_args => 1,
        #     order       => 400,
        # },
    };
    return $actions;

}

sub _list_actions_alt_tmpl {
    my $actions = {
        delete => {
            button      => 1,
            label       => 'Delete',
            mode        => 'delete',
            class       => 'icon-action',
            return_args => 1,
            args        => { _type => 'alttemplate' },
            order       => 300,
        },
        enable_alttemplates => {
            button      => 1,
            label       => 'Enabled',
            mode        => 'change_status_alttemplate',
            class       => 'icon-action',
            return_args => 1,
            order       => 400,
        },
        disable_alttemplates => {
            button      => 1,
            label       => 'Disabled',
            mode        => 'change_status_alttemplate',
            return_args => 1,
            order       => 500,
        },
        export_alttemplates => {
            label       => 'Export',
            mode        => 'export_alttemplates',
            return_args => 1,
            order       => 700,
        },
    };
    return $actions;
}

sub _list_actions_customschema {
    my $component = MT->component( 'Developer' );
    my $actions = {
        delete => {
            button      => 1,
            label       => 'Delete',
            mode        => 'delete',
            class       => 'icon-action',
            return_args => 1,
            args        => { _type => 'customschema' },
            order       => 300,
        },
        export_customschema => {
            button      => 0,
            label       => 'Export Plugin',
            mode        => 'customschemas_to_plugin',
            return_args => 1,
            order       => 600,
            input       => 1,
            input_label => $component->translate( 'Enter a Plugin Name' ),
        },
    };
    return $actions;
}


sub _system_filters {
    my $component = MT->component( 'Developer' );
    my $filters = {
        enabled_jobs => {
            label => $component->translate( 'Enabled Custom Handlers' ),
            items => [
                {   type => 'status',
                    args => { value => 2 },
                }
            ],
            order => 200,
        },
        disabled_jobs => {
            label => $component->translate( 'Disabled Custom Handlers' ),
            items => [
                {   type => 'status',
                    args => { value => 1 },
                }
            ],
            order => 300,
        },
    };
    return $filters;
}

sub _system_filters_alttemplate {
    my $component = MT->component( 'Developer' );
    my $filters = {
        enabled_jobs => {
            label => $component->translate( 'Enabled Alt Templates' ),
            items => [
                {   type => 'status',
                    args => { value => 2 },
                }
            ],
            order => 200,
        },
        disabled_jobs => {
            label => $component->translate( 'Disabled Alt Templates' ),
            items => [
                {   type => 'status',
                    args => { value => 1 },
                }
            ],
            order => 300,
        },
    };
    return $filters;
}

1;