process PREPROC_EDDY {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilus:2.2.2"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(rev_dwi), path(rev_bval), path(rev_bvec), path(corrected_b0s), path(topup_fieldcoef), path(topup_movpart)

    output:
        tuple val(meta), path("*__dwi_corrected.nii.gz")                , emit: dwi_corrected
        tuple val(meta), path("*__dwi_eddy_corrected.bval")             , emit: bval_corrected
        tuple val(meta), path("*__dwi_eddy_corrected.bvec")             , emit: bvec_corrected
        tuple val(meta), path("*__b0_bet_mask.nii.gz")                  , emit: b0_mask
        tuple val(meta), env("nan_percentage")                          , emit: nan_percentage
        tuple val(meta), path("*__dwi_eddy_mqc.gif")                    , emit: dwi_eddy_mqc, optional:true
        tuple val(meta), path("*__rev_dwi_eddy_mqc.gif")                , emit: rev_dwi_eddy_mqc, optional:true
        tuple val(meta), path("*__dwi_eddy_restricted_movement_rms.txt"), emit: eddy_fd_mqc, optional:true
        path "versions.yml"                                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def slice_drop_flag = task.ext.slice_drop_correction ? "--slice_drop_correction " : ""
    def bet_topup_before_eddy_f = task.ext.bet_topup_before_eddy_f ?: ""
    def prefix_topup = task.ext.prefix_topup ? task.ext.prefix_topup : ""
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ? task.ext.b0_thr_extract_b0 : ""
    def encoding = meta.dir ?: (task.ext.encoding ?: "")
    def readout = meta.readout ?: (task.ext.readout ?: "")
    def dilate_b0_mask_prelim_brain_extraction = task.ext.dilate_b0_mask_prelim_brain_extraction ? task.ext.dilate_b0_mask_prelim_brain_extraction : ""
    def eddy_cmd = task.ext.eddy_cmd ? task.ext.eddy_cmd : "eddy_cpu"
    def bet_prelim_f = task.ext.bet_prelim_f ? task.ext.bet_prelim_f : ""
    def run_qc = task.ext.run_qc ? task.ext.run_qc : false
    def nthreads_mrtrix = task.ext.single_thread ? "-nthreads 0" : "-nthreads ${task.cpus}"
    def nthreads = task.ext.single_thread ? 1 : task.cpus
    def extra_args = task.ext.extra_args ?: ""
    if (eddy_cmd == "eddy_cpu") {
        extra_args += " --nthr=${nthreads} "
    }

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export ANTS_RANDOM_SEED=${task.ext.ants_rng_seed ? task.ext.ants_rng_seed : "1234"}
    export MRTRIX_RNG_SEED=${task.ext.mrtrix_rng_seed ? task.ext.mrtrix_rng_seed : "1234"}

    nan_percentage=0

    orig_bval=$bval
    # Concatenate DWIs
    number_rev_dwi=0
    if [[ -f "$rev_dwi" ]];
    then
        scil_dwi_concatenate ${prefix}__concatenated_dwi.nii.gz ${prefix}__concatenated_dwi.bval ${prefix}__concatenated_dwi.bvec -f\
            --in_dwis ${dwi} ${rev_dwi} --in_bvals ${bval} ${rev_bval}\
            --in_bvecs ${bvec} ${rev_bvec}

        number_rev_dwi=\$(scil_header_print_info ${rev_dwi} --key dim | sed "s/  / /g" | sed "s/  / /g" | rev | cut -d' ' -f4-4 | rev)

        dwi=${prefix}__concatenated_dwi.nii.gz
        bval=${prefix}__concatenated_dwi.bval
        bvec=${prefix}__concatenated_dwi.bvec
    else
        dwi=${dwi}
        bval=${bval}
        bvec=${bvec}
    fi

    # If topup has been run before
    if [[ -f "$topup_fieldcoef" ]]
    then
        mrconvert $corrected_b0s b0_corrected.nii.gz -coord 3 0 -axes 0,1,2 ${nthreads_mrtrix}
        bet b0_corrected.nii.gz ${prefix}__b0_bet.nii.gz -m -R\
            -f $bet_topup_before_eddy_f

        scil_dwi_prepare_eddy_command \${dwi} \${bval} \${bvec} ${prefix}__b0_bet_mask.nii.gz\
            --topup $prefix_topup --eddy_cmd $eddy_cmd\
            --b0_thr $b0_thr_extract_b0\
            --encoding_direction $encoding\
            --readout $readout --out_script --fix_seed\
            --n_reverse \${number_rev_dwi}\
            --lsr_resampling\
            $slice_drop_flag
    else
        scil_dwi_extract_b0 \${dwi} \${bval} \${bvec} ${prefix}__b0.nii.gz --mean\
            --b0_threshold $b0_thr_extract_b0 --skip_b0_check
        bet ${prefix}__b0.nii.gz ${prefix}__b0_bet.nii.gz -m -R -f $bet_prelim_f
        scil_volume_math convert ${prefix}__b0_bet_mask.nii.gz ${prefix}__b0_bet_mask.nii.gz --data_type uint8 -f
        maskfilter ${prefix}__b0_bet_mask.nii.gz dilate ${prefix}__b0_bet_mask_dilated.nii.gz\
            --npass $dilate_b0_mask_prelim_brain_extraction ${nthreads_mrtrix}
        scil_volume_math multiplication ${prefix}__b0.nii.gz ${prefix}__b0_bet_mask_dilated.nii.gz\
            ${prefix}__b0_bet.nii.gz --data_type float32 -f

        scil_dwi_prepare_eddy_command \${dwi} \${bval} \${bvec} ${prefix}__b0_bet_mask.nii.gz\
            --eddy_cmd $eddy_cmd --b0_thr $b0_thr_extract_b0\
            --encoding_direction $encoding\
            --readout $readout --out_script --fix_seed\
            $slice_drop_flag
    fi

    echo "--very_verbose $extra_args" >> eddy.sh
    sh eddy.sh
    scil_volume_math lower_clip dwi_eddy_corrected.nii.gz 0 ${prefix}__dwi_corrected.nii.gz

    if [[ \$number_rev_dwi -eq 0 ]]
    then
        mv dwi_eddy_corrected.eddy_rotated_bvecs ${prefix}__dwi_eddy_corrected.bvec
        mv \${orig_bval} ${prefix}__dwi_eddy_corrected.bval
    else
        scil_gradients_validate_correct_eddy dwi_eddy_corrected.eddy_rotated_bvecs \${bval} \${number_rev_dwi} ${prefix}__dwi_eddy_corrected.bvec ${prefix}__dwi_eddy_corrected.bval
    fi

    # Rename framewise displacement file to include subject id
    mv dwi_eddy_corrected.eddy_restricted_movement_rms ${prefix}__dwi_eddy_restricted_movement_rms.txt

    nb_voxels=\$(mrstats ${prefix}__dwi_corrected.nii.gz -mask ${prefix}__b0_bet_mask.nii.gz -quiet -output count -allvolumes)
    nb_nan=\$(mrcalc ${prefix}__dwi_corrected.nii.gz  -isnan - | mrstats - -quiet -output count -ignorezero -allvolumes)
    nan_percentage=\$(awk "BEGIN {print \${nb_nan} * 100 / \${nb_voxels}}")

    if [[ \${nan_percentage} -gt 0 ]];
    then
        echo "Warning: \${nan_percentage}% of voxels in the brain mask are NaN after eddy correction."
        mrcalc ${prefix}__dwi_corrected.nii.gz -finite ${prefix}__dwi_corrected.nii.gz 0.0 -if ${prefix}__dwi_corrected.nii.gz -force
    fi

    if $run_qc;
    then
        extract_dim=\$(mrinfo ${dwi} -size)
        read sagittal_dim coronal_dim axial_dim fourth_dim <<< "\${extract_dim}"

        # Get the middle slice
        coronal_dim=\$((\$coronal_dim / 2))
        axial_dim=\$((\$axial_dim / 2))
        sagittal_dim=\$((\$sagittal_dim / 2))

        viz_params="--display_slice_number --display_lr --size 256 256"
        rev_dwi=""
        if [[ -f "$rev_dwi" ]];
        then
            scil_dwi_powder_average ${rev_dwi} ${prefix}__dwi_eddy_corrected.bval ${prefix}__rev_dwi_powder_average.nii.gz
            scil_volume_math normalize_max ${prefix}__rev_dwi_powder_average.nii.gz ${prefix}__rev_dwi_powder_average_norm.nii.gz
            rev_dwi="rev_dwi"
        fi
        scil_dwi_powder_average ${dwi} ${prefix}__dwi_eddy_corrected.bval ${prefix}__dwi_powder_average.nii.gz
        scil_dwi_powder_average ${prefix}__dwi_corrected.nii.gz ${prefix}__dwi_eddy_corrected.bval ${prefix}__dwi_corrected_powder_average.nii.gz
        scil_volume_math normalize_max ${prefix}__dwi_powder_average.nii.gz ${prefix}__dwi_powder_average_norm.nii.gz
        scil_volume_math normalize_max ${prefix}__dwi_corrected_powder_average.nii.gz ${prefix}__dwi_corrected_powder_average_norm.nii.gz

        for image in dwi_corrected dwi \${rev_dwi}
        do
            mrconvert ${prefix}__\${image}_powder_average_norm.nii.gz ${prefix}__\${image}_powder_average_norm_viz.nii.gz -stride -1,2,3 ${nthreads_mrtrix}
            scil_viz_volume_screenshot ${prefix}__\${image}_powder_average_norm_viz.nii.gz ${prefix}__\${image}_coronal.png \${viz_params} --slices \${coronal_dim} --axis coronal
            scil_viz_volume_screenshot ${prefix}__\${image}_powder_average_norm_viz.nii.gz ${prefix}__\${image}_axial.png \${viz_params} --slices \${axial_dim} --axis axial
            scil_viz_volume_screenshot ${prefix}__\${image}_powder_average_norm_viz.nii.gz ${prefix}__\${image}_sagittal.png \${viz_params} --slices \${sagittal_dim} --axis sagittal

            if [ \$image == "dwi_corrected" ] || [ \$image == "rev_dwi" ]
            then
                title="After"
            else
                title="Before"
            fi

            convert +append ${prefix}__\${image}_coronal_slice_\${coronal_dim}.png \
                    ${prefix}__\${image}_axial_slice_\${axial_dim}.png  \
                    ${prefix}__\${image}_sagittal_slice_\${sagittal_dim}.png \
                    ${prefix}__\${image}.png

            convert -annotate +20+230 "\${title}" -fill white -pointsize 30 ${prefix}__\${image}.png ${prefix}__\${image}.png
        done

        if [[ -f "$rev_dwi" ]];
        then
            convert -delay 10 -loop 0 -morph 10 \
                ${prefix}__rev_dwi.png ${prefix}__dwi_corrected.png ${prefix}__rev_dwi.png \
                ${prefix}__rev_dwi_eddy_mqc.gif
        fi

        convert -delay 10 -loop 0 -morph 10 \
                ${prefix}__dwi.png ${prefix}__dwi_corrected.png ${prefix}__dwi.png \
                ${prefix}__dwi_eddy_mqc.gif

        rm -rf *png
        rm -rf *powder_average*
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def values = meta.values() as List
    prefix = values.size() > 1 ? "${meta.id}_${values[1]}" : meta.id

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    scil_volume_math -h
    maskfilter -h
    bet -h
    scil_dwi_extract_b0 -h
    scil_gradients_validate_correct_eddy -h
    scil_dwi_concatenate -h
    mrconvert -h
    scil_dwi_prepare_eddy_command -h
    scil_header_print_info -h
    scil_viz_volume_screenshot -h
    convert

    touch ${prefix}__dwi_corrected.nii.gz
    touch ${prefix}__dwi_eddy_mqc.gif
    touch ${prefix}__rev_dwi_eddy_mqc.gif
    touch ${prefix}__dwi_eddy_corrected.bval
    touch ${prefix}__dwi_eddy_corrected.bvec
    touch ${prefix}__b0_bet_mask.nii.gz
    touch ${prefix}__dwi_eddy_restricted_movement_rms.txt
    nan_percentage=1

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
    END_VERSIONS
    """
}
