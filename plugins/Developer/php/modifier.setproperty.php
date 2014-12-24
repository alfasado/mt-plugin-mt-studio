<?php
function smarty_modifier_setproperty( $value, $name, $blog_id ) {
    $mt = MT::get_instance();
    $ctx =& $mt->context();
    $name = $ctx->mt->db()->escape( $name );
    // $value = $ctx->mt->db()->escape( $value );
    if ( isset( $blog_id ) ) {
        $blog_id = $ctx->mt->db()->escape( $blog_id );
    }
    if (! $blog_id ) $blog_id = 0;
    $ctx->stash( "developer_property:${blog_id}:${name}", $value );
    require_once( 'class.mt_property.php' );
    $_prop = new Property;
    $prop = $_prop->Find( "property_blog_id=${blog_id} AND property_name='${name}'" );
    if ( is_array( $prop ) ) {
        $prop = $prop[ 0 ];
        if ( $prop->property_text != $value ) {
            $prop->property_text = $value;
            $prop->Update();
        }
    } else {
        $prop = new Property;
        $prop->property_text = $value;
        $prop->property_blog_id = $blog_id;
        $prop->property_name = $name;
        $prop->Save();
    }
    return '';

    // global $app;
    // $component = $app->component( 'Developer' );
    // if ( $blog_id ) {
    //     $plugindata = $component->get_config_value( 'developer_property', 'blog:' . $blog_id );
    // } else {
    //     $plugindata = $component->get_config_value( 'developer_property' );
    // }
    // if ( $plugindata ) {
    //     $data = json_decode( $plugindata, TRUE );
    // } else {
    //     $data = array();
    // }
    // $data[ $name ] = $value;
    // $data = json_encode( $data );
    // // plugin_config:configuration:developer
    // $get_from = 'configuration';
    // if ( $blog_id ) {
    //     $component->set_config_value( 'developer_property', $data, 'blog:' . $blog_id );
    //     $get_from .= ":blog:$blog_id";
    // } else {
    //     $component->set_config_value( 'developer_property', $data );
    // }
    // $component->stash( "plugin_config:${get_from}:developer", '' );
    // $app->stash( "plugin_config:${get_from}:developer", '' );
}
?>