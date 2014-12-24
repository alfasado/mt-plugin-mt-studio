<?php
function smarty_function_mtassetthumbnailfile( $args, &$ctx ) {
    $asset = $ctx->stash( 'asset' );
    if (! $asset ) return '';
    if ( $asset->asset_class != 'image' ) return '';
    $blog = $ctx->stash( 'blog' );
    if (! $blog ) return '';
    require_once( 'MTUtil.php' );
    list( $thumb,$w,$h,$dest ) = get_thumbnail_file( $asset, $blog, $args );
    return $dest;
}
?>