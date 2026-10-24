
process REGISTRATION_COBRALABANTS {
    tag "$meta.id"
    label 'process_medium'

    container "scilus/scilus:2.3.0"

    input:
        tuple val(meta), path(fixed_image), path(moving_image), path(fixed_mask), path(moving_mask) //** optional, input = [] **//

    output:
        tuple val(meta), path("*_warped.nii.gz")                           , emit: image_warped
        tuple val(meta), path("*_warped_reference.nii.gz")                 , emit: fixed_warped
        tuple val(meta), path("*_forward1_affine.mat")                     , emit: forward_affine, optional: true
        tuple val(meta), path("*_forward0_warp.nii.gz")                    , emit: forward_warp, optional: true
        tuple val(meta), path("*_backward1_warp.nii.gz")                   , emit: backward_warp, optional: true
        tuple val(meta), path("*_backward0_affine.mat")                    , emit: backward_affine, optional: true
        tuple val(meta), path("*_forward*.{nii.gz,mat}", arity: '1..2')    , emit: forward_image_transform
        tuple val(meta), path("*_backward*.{nii.gz,mat}", arity: '1..2')   , emit: backward_image_transform
        tuple val(meta), path("*_backward*.{nii.gz,mat}", arity: '1..2')   , emit: forward_tractogram_transform
        tuple val(meta), path("*_forward*.{nii.gz,mat}", arity: '1..2')    , emit: backward_tractogram_transform
        tuple val(meta), path("*_registration_cobralabants_mqc.gif")       , emit: mqc, optional: true
        path "versions.yml"                                                , emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? "${task.ext.suffix}_warped" : "warped"
    def suffix_qc = task.ext.suffix_qc ?: ""
    def run_qc = task.ext.run_qc as Boolean || false

    if ( (task.ext.masking_strategy == "both" || task.ext.masking_strategy == "internal") && (fixed_mask || moving_mask) ) {
        if ( fixed_mask ) args += " --fixed-mask $fixed_mask"
        if ( moving_mask ) args += " --moving-mask $moving_mask"
    }
    if ( task.ext.initial_transform ) args += " --initial-transform $task.ext.initial_transform"
    if ( task.ext.float ) args += " --float"
    if ( task.ext.float_linear ) args += " --float-linear"
    if ( task.ext.float_nonlinear ) args += " --float-nonlinear"
    if ( task.ext.histogram_matching ) args += " --histogram-matching"
    if ( task.ext.rough ) args += " --rough"
    if ( task.ext.fast ) args += " --fast"
    if ( task.ext.mask_extract ) args += " --mask-extract"
    if ( task.ext.mask_all_linear ) args += " --mask-all-linear"
    if ( task.ext.keep_mask_after_extract ) args += " --keep-mask-after-extract"
    if ( task.ext.resampled_linear_output ) args += " --resampled-linear-output $task.ext.resampled_linear_output"
    if ( task.ext.linear_type ) args += " --linear-type $task.ext.linear_type"
    if ( task.ext.close ) args += " --close"
    if ( task.ext.convergence && task.ext.convergence != 1e-6 ) args += " --convergence $task.ext.convergence"
    if ( task.ext.skip_linear ) args += " --skip-linear"
    if ( task.ext.linear_metric && task.ext.linear_metric != 'Mattes' ) args += " --linear-metric $task.ext.linear_metric"
    if ( task.ext.linear_shrink_factors ) args += " --linear-shrink-factors $task.ext.linear_shrink_factors"
    if ( task.ext.linear_smoothing_sigmas ) args += " --linear-smoothing-sigmas $task.ext.linear_smoothing_sigmas"
    if ( task.ext.linear_convergence ) args += " --linear-convergence $task.ext.linear_convergence"
    if ( task.ext.final_iterations_linear && task.ext.final_iterations_linear != 50 ) args += " --final-iterations-linear $task.ext.final_iterations_linear"
    if ( task.ext.kmeans_transformed_linear ) args += " --kmeans-transformed-linear"
    if ( task.ext.skip_nonlinear ) args += " --skip-nonlinear"
    if ( task.ext.syn_control && task.ext.syn_control != '0.4,4,0' ) args += " --syn-control $task.ext.syn_control"
    if ( task.ext.syn_metric && task.ext.syn_metric != 'CC[4]' ) args += " --syn-metric $task.ext.syn_metric"
    if ( task.ext.syn_shrink_factors ) args += " --syn-shrink-factors $task.ext.syn_shrink_factors"
    if ( task.ext.syn_smoothing_sigmas ) args += " --syn-smoothing-sigmas $task.ext.syn_smoothing_sigmas"
    if ( task.ext.syn_convergence ) args += " --syn-convergence $task.ext.syn_convergence"
    if ( task.ext.final_iterations_nonlinear && task.ext.final_iterations_nonlinear != 20 ) args += " --final-iterations-nonlinear $task.ext.final_iterations_nonlinear"
    if ( task.ext.winsorize_image_intensities ) args += " --winsorize-image-intensities $task.ext.winsorize_image_intensities"
    if ( task.ext.clobber ) args += " --clobber"
    if ( task.ext.verbose == false ) args += " --no-verbose"
    if ( task.ext.debug ) args += " --debug"
    if ( task.ext.reproducibility ) args += " --reproducibility"
    if ( task.ext.ants_rng_seed ) args += " --random-seed $task.ext.ants_rng_seed"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export ANTS_RANDOM_SEED=${task.ext.ants_rng_seed ?: 1234}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    moving_base=\$(basename "${moving_image}")
    ext=\${moving_base#*.}
    moving_id=\${moving_base%.\${ext}}
    moving_id=\${moving_id#${prefix}_*}

    antsRegistration_affine_SyN.sh $args --resampled-output ${prefix}_\${moving_id}_${suffix}.nii.gz $moving_image $fixed_image output

    mv output0GenericAffine.mat ${prefix}_forward1_affine.mat

    if [ "${task.ext.skip_nonlinear}" != "true" ]; then
        mv output1InverseWarp.nii.gz ${prefix}_backward1_warp.nii.gz
        mv output1Warp.nii.gz ${prefix}_forward0_warp.nii.gz
    fi

    antsApplyTransforms -d 3 -t "[${prefix}_forward1_affine.mat,1]" \
        -o "Linear[${prefix}_backward0_affine.mat]"

    if [ "${task.ext.skip_nonlinear}" != "true" ]; then
        antsApplyTransforms -d 3 -i $fixed_image -r $moving_image -n Linear \
            -t "[${prefix}_backward0_affine.mat,1]" \
            -t ${prefix}_backward1_warp.nii.gz \
            -o ${prefix}_warped_reference.nii.gz
    else
        antsApplyTransforms -d 3 -i $fixed_image -r $moving_image -n Linear \
            -t "[${prefix}_backward0_affine.mat,1]" \
            -o ${prefix}_warped_reference.nii.gz
    fi

    ### ** QC ** ###
    if $run_qc; then
        mv $fixed_image fixed_image.nii.gz
        extract_dim=\$(mrinfo fixed_image.nii.gz -size)
        read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"

        # Get the middle slice
        coronal_dim=\$((\$coronal_dim / 2))
        axial_dim=\$((\$axial_dim / 2))
        sagittal_dim=\$((\$sagittal_dim / 2))

        # Get fixed ID, moving ID already computed
        fixed_base=\$(basename "${fixed_image}")
        ext=\${fixed_base#*.}
        fixed_id=\${fixed_base%.\${ext}}
        fixed_id=\${fixed_id#${prefix}_*}

        # Set viz params.
        viz_params="--display_slice_number --display_lr --size 256 256"
        # Iterate over images.
        for image in fixed_image warped; do
            mrconvert *\${image}.nii.gz \${image}_viz.nii.gz -stride -1,2,3
            scil_viz_volume_screenshot \${image}_viz.nii.gz \${image}_coronal.png \
                --slices \$coronal_dim --axis coronal \$viz_params
            scil_viz_volume_screenshot \${image}_viz.nii.gz \${image}_sagittal.png \
                --slices \$sagittal_dim --axis sagittal \$viz_params
            scil_viz_volume_screenshot \${image}_viz.nii.gz \${image}_axial.png \
                --slices \$axial_dim --axis axial \$viz_params

            if [ \$image != fixed_image ]; then
                title="Warped \${moving_id^^}"
            else
                title="Reference \${fixed_id^^}"
            fi

            convert +append \${image}_coronal*.png \${image}_axial*.png \
                \${image}_sagittal*.png \${image}_mosaic.png
            convert -annotate +20+230 "\${title}" -fill white -pointsize 30 \
                \${image}_mosaic.png \${image}_mosaic.png

            # Clean up.
            rm \${image}_coronal*.png \${image}_sagittal*.png \${image}_axial*.png
        done

        # Create GIF.
        convert -delay 10 -loop 0 -morph 10 \
            warped_mosaic.png fixed_image_mosaic.png warped_mosaic.png \
            ${prefix}_${suffix_qc}_registration_cobralabants_mqc.gif

        # Clean up.
        rm *_mosaic.png
    fi

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
    def suffix = task.ext.suffix ? "${task.ext.suffix}_warped" : "warped"
    def suffix_qc = task.ext.suffix_qc ?: ""
    def run_qc = task.ext.run_qc as Boolean || false

    """
    set +e
    function handle_code () {
        local code=\$?
        ignore=( 1 )
        [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }

    # Local trap to ignore awaited non-zero exit codes
    {
        trap 'handle_code' ERR
        antsRegistration_affine_SyN.sh -h
    }

    antsApplyTransforms -h
    convert -help .
    scil_viz_volume_screenshot -h

    moving_base=\$(basename "${moving_image}")
    ext=\${moving_base#*.}
    moving_id=\${moving_base%.\${ext}}
    moving_id=\${moving_id#${prefix}_*}

    touch ${prefix}_\${moving_id}_${suffix}.nii.gz
    touch ${prefix}_warped_reference.nii.gz
    touch ${prefix}_forward1_affine.mat
    touch ${prefix}_forward0_warp.nii.gz
    touch ${prefix}_backward1_warp.nii.gz
    touch ${prefix}_backward0_affine.mat

    if $run_qc; then
        touch ${prefix}_${suffix_qc}_registration_cobralabants_mqc.gif
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        imagemagick: \$(convert -version | grep "Version:" | sed -E 's/.*ImageMagick ([0-9.-]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
