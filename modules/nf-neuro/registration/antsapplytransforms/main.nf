process REGISTRATION_ANTSAPPLYTRANSFORMS {
    tag "$meta.id"
    label 'process_low'

    container "scilus/scilus:2.2.1"

    input:
    tuple val(meta), path(images, arity: '1..*'), path(reference), path(transformations, arity: '1..*')

    output:
    tuple val(meta), path("*.{nii,nii.gz}")                             , emit: warped_image
    tuple val(meta), path("*_registration_antsapplytransforms_mqc.gif") , emit: mqc, optional: true
    path "versions.yml"                                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "warped"
    def suffix_qc = task.ext.suffix_qc ? "_${task.ext.suffix_qc}" : ""

    def dimensionality = "-d ${task.ext.dimensionality ?: 3}"
    def image_type = "-e ${task.ext.image_type ?: 0}"
    def interpolation = "-n ${task.ext.interpolation ?: "Linear"}"
    def output_dtype = "-u ${task.ext.output_dtype ?: "default"}"
    def default_val = "-f ${task.ext.default_val ?: 0}"
    def run_qc = task.ext.run_qc as Boolean || false

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    for image in $images; do
        ext=\${image#*.}
        bname=\$(basename \${image} .\${ext})

        antsApplyTransforms $dimensionality \
            -i \$image \
            -r $reference \
            -o ${prefix}_\${bname}_${suffix}.nii.gz \
            $interpolation \
            ${transformations.collect{ t -> "-t $t" }.join(" ")} \
            $output_dtype \
            $image_type \
            $default_val

        ### ** QC ** ###
        if $run_qc; then
            ln -sf $reference reference.nii.gz
            extract_dim=\$(mrinfo ${prefix}_\${bname}_${suffix}.nii.gz -size)
            read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"

            # Get the middle slice
            coronal_dim=\$((\$coronal_dim / 2))
            axial_dim=\$((\$axial_dim / 2))
            sagittal_dim=\$((\$sagittal_dim / 2))

            # Set viz params.
            viz_params="--display_slice_number --display_lr --size 256 256"

            # Iterate over images.
            for image in reference \${bname}_${suffix}; do
                mrconvert *\${image}.nii.gz *\${image}_viz.nii.gz -stride -1,2,3 -force
                scil_viz_volume_screenshot *\${image}_viz.nii.gz \${image}_coronal.png \
                    --slices \$coronal_dim --axis coronal \$viz_params
                scil_viz_volume_screenshot *\${image}_viz.nii.gz \${image}_sagittal.png \
                    --slices \$sagittal_dim --axis sagittal \$viz_params
                scil_viz_volume_screenshot *\${image}_viz.nii.gz \${image}_axial.png \
                    --slices \$axial_dim --axis axial \$viz_params

                if [ \$image != reference ]; then
                    title="Transformed"
                else
                    title="Reference"
                fi

                convert +append \${image}_coronal*.png \${image}_axial*.png \
                    \${image}_sagittal*.png \${image}_mosaic.png
                convert -annotate +20+230 "\${title}" -fill white -pointsize 30 \
                    \${image}_mosaic.png \${image}_mosaic.png
                # Clean up.
                rm \${image}_coronal*.png \${image}_sagittal*.png \${image}_axial*.png
                rm *\${image}_viz.nii.gz
            done

            # Create GIF.
            convert -delay 10 -loop 0 -morph 10 \
                \${bname}_${suffix}_mosaic.png reference_mosaic.png \${bname}_${suffix}_mosaic.png \
                ${prefix}_\${bname}${suffix_qc}_registration_antsapplytransforms_mqc.gif

            # Clean up.
            rm *_mosaic.png
            rm reference.nii.gz
        fi
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        imagemagick: \$(convert -version | grep "Version:" | sed -E 's/.*ImageMagick ([0-9.-]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "warped"
    def suffix_qc = task.ext.suffix_qc ? "_${task.ext.suffix_qc}" : ""
    def run_qc = task.ext.run_qc as Boolean || false

    """
    antsApplyTransforms -h
    scil_viz_volume_screenshot -h
    convert -help .

    for image in $images; do
        ext=\${image#*.}
        bname=\$(basename \${image} .\${ext})

        touch ${prefix}_\${bname}_${suffix}.nii.gz

        if $run_qc; then
            touch ${prefix}_\${bname}${suffix_qc}_registration_antsapplytransforms_mqc.gif
        fi
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        imagemagick: \$(convert -version | grep "Version:" | sed -E 's/.*ImageMagick ([0-9.-]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
