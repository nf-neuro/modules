process QC_GIF {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
    tuple val(meta), path(image1), path(image2)

    output:
    tuple val(meta), path("*_screenshots_merged_mqc.gif"), emit: mqc_screenshots
    path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def title_image1 = task.ext.title_image1 ? task.ext.title_image1 : "image1"
    def title_image2 = task.ext.title_image2 ? task.ext.title_image2 : "image2"
    def suffix_qc = task.ext.suffix_qc ? "${task.ext.suffix_qc}" : ""

    """
    if [[ -f "$image2" ]]; then
    # Get the middle slice.
        for image in $image1 $image2;
            do
            dim=\$(mrinfo \${image} -ndim)
            extract_dim=\$(mrinfo \${image} -size)
            if [ "\$dim" == 3 ];
            then
                read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"
            elif [ "\$dim" == 4 ];
            then
                read sagittal_dim coronal_dim axial_dim forth_dim <<< "\${extract_dim}"
            fi
            sagittal_dim=\$((\$sagittal_dim / 2))
            coronal_dim=\$((\$coronal_dim / 2))
            axial_dim=\$((\$axial_dim / 2))

            basename=\$(basename \$image .nii.gz)
            mrconvert \${image} \${basename}_for_viz.nii.gz -stride -1,2,3 -force

            # Set viz params.
            viz_params="--display_slice_number --display_lr --size 256 256"

            scil_viz_volume_screenshot \${basename}_for_viz.nii.gz \${basename}_coronal.png \
                --slices \$coronal_dim --axis coronal \$viz_params
            scil_viz_volume_screenshot \${basename}_for_viz.nii.gz \${basename}_sagittal.png \
                --slices \$sagittal_dim --axis sagittal \$viz_params
            scil_viz_volume_screenshot \${basename}_for_viz.nii.gz \${basename}_axial.png \
                --slices \$axial_dim --axis axial \$viz_params
            if [ \$image = $image1 ];
            then
                title="$title_image1"
            else
                title="$title_image2"
            fi
            convert +append \${basename}_coronal*.png \${basename}_axial*.png \
                \${basename}_sagittal*.png \${basename}_mosaic.png
            convert -annotate +20+230 "\${title}" -fill white -pointsize 30 \
                \${basename}_mosaic.png \${basename}_mosaic.png
            # Clean up.
            rm \${basename}_coronal*.png \${basename}_sagittal*.png \${basename}_axial*.png
        done

        # Create GIF.
        image1=\$(basename $image1 .nii.gz)
        image2=\$(basename $image2 .nii.gz)
        convert -delay 10 -loop 0 -morph 10 \
            \${image1}_mosaic.png \${image2}_mosaic.png \
            ${prefix}_${suffix_qc}_screenshots_merged_mqc.gif
        # Clean up.
        rm *_mosaic.png

    else
        dim=\$(mrinfo $image1 -ndim)
        extract_dim=\$(mrinfo $image1 -size)
        basename=\$(basename $image1 .nii.gz)
        echo "Dimension de l'image : \$dim"
        echo "Tailles des dimensions : \$extract_dim"

        mrconvert $image1 base_image_viz.nii.gz -stride -1,2,3 -force

        if [ "\$dim" == 3 ]; then
            echo "Error: If you only use one input, it must be in 4D to create the gif." >&2
            exit 1
        elif [ "\$dim" == 4 ]; then
            read sagittal_dim coronal_dim axial_dim forth_dim <<< "\${extract_dim}"
            sagittal_dim=\$((\$sagittal_dim / 2))
            coronal_dim=\$((\$coronal_dim / 2))
            axial_dim=\$((\$axial_dim / 2))

            # Set viz params.
            viz_params="--display_slice_number --display_lr --size 256 256"

            for ((slice=0; slice<\$forth_dim; slice++)); do
                echo "Slice : \$slice"
                mrconvert base_image_viz.nii.gz -coord 3 \${slice} -axes 0,1,2 image.nii.gz -force

                scil_viz_volume_screenshot image.nii.gz \${basename}_coronal.png \
                    --slices \$coronal_dim --axis coronal \$viz_params
                scil_viz_volume_screenshot image.nii.gz \${basename}_sagittal.png \
                    --slices \$sagittal_dim --axis sagittal \$viz_params
                scil_viz_volume_screenshot image.nii.gz \${basename}_axial.png \
                    --slices \$axial_dim --axis axial \$viz_params

                title="${title_image1}_\$slice"

                convert +append \${basename}_coronal*.png \${basename}_axial*.png \
                    \${basename}_sagittal*.png \${basename}_\${slice}_mosaic.png
                convert -annotate +20+230 "\${title}" -fill white -pointsize 30 \
                    \${basename}_\${slice}_mosaic.png \${basename}_\${slice}_mosaic.png

                # Clean up.
                rm \${basename}_coronal*.png \${basename}_sagittal*.png \${basename}_axial*.png
            done

            convert -delay 10 -loop 0 -morph 10 \${basename}*_mosaic.png \
                ${prefix}_${suffix_qc}_screenshots_merged_mqc.gif
        fi
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | grep "Version:" | sed -E 's/.*ImageMagick ([0-9.-]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix_qc = task.ext.suffix_qc ? "${task.ext.suffix_qc}" : ""
    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    mrinfo -h
    mrconvert -h
    scil_viz_volume_screenshot -h
    convert -h

    touch ${prefix}_${suffix_qc}_screenshots_merged_mqc.gif

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | grep "Version:" | sed -E 's/.*ImageMagick ([0-9.-]+).*/\\1/')
    END_VERSIONS
    """
}
