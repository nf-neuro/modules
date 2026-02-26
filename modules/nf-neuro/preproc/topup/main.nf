process PREPROC_TOPUP {
    tag "$meta.id"
    label 'process_medium'

    container "scilus/scilus:2.2.1"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(b0), path(rev_dwi), path(rev_bval), path(rev_bvec), path(rev_b0)
        val config_topup

    output:
        tuple val(meta), path("*__corrected_b0s.nii.gz"), emit: topup_corrected_b0s
        tuple val(meta), path("*_fieldcoef.nii.gz")     , emit: topup_fieldcoef
        tuple val(meta), path("*_movpar.txt")           , emit: topup_movpart
        tuple val(meta), path("*__rev_b0_warped.nii.gz"), emit: rev_b0_warped
        tuple val(meta), path("*__rev_b0_mean.nii.gz")  , emit: rev_b0_mean
        tuple val(meta), path("*__b0_mean.nii.gz")      , emit: b0_mean
        tuple val(meta), path("*_b0_topup_mqc.gif")     , emit: mqc   , optional: true
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def prefix_topup = task.ext.prefix_topup ?: ""
    config_topup = config_topup ?: task.ext.default_config_topup
    def encoding = task.ext.encoding ?: ""
    def readout = task.ext.readout ?: ""
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: ""
    def run_qc = task.ext.run_qc

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export ANTS_RANDOM_SEED=7468

    if [[ -f "$b0" ]];
    then
        scil_volume_math concatenate $b0 $b0 ${prefix}__concatenated_b0.nii.gz --data_type float32
        scil_volume_math mean ${prefix}__concatenated_b0.nii.gz ${prefix}__b0_mean.nii.gz
    else
        scil_dwi_extract_b0 $dwi $bval $bvec ${prefix}__b0_mean.nii.gz --mean --b0_threshold $b0_thr_extract_b0 --skip_b0_check
    fi

    if [[ -f "$rev_b0" ]];
    then
        scil_volume_math concatenate $rev_b0 $rev_b0 ${prefix}__concatenated_rev_b0.nii.gz --data_type float32
        scil_volume_math mean ${prefix}__concatenated_rev_b0.nii.gz ${prefix}__rev_b0_mean.nii.gz
    else
        scil_dwi_extract_b0 $rev_dwi $rev_bval $rev_bvec ${prefix}__rev_b0_mean.nii.gz --mean --b0_threshold $b0_thr_extract_b0 --skip_b0_check
    fi

    antsRegistrationSyNQuick.sh -d 3 -f ${prefix}__b0_mean.nii.gz -m ${prefix}__rev_b0_mean.nii.gz -o output -t r -e 1
    mv outputWarped.nii.gz ${prefix}__rev_b0_warped.nii.gz
    scil_dwi_prepare_topup_command ${prefix}__b0_mean.nii.gz ${prefix}__rev_b0_warped.nii.gz\
        --config $config_topup\
        --encoding_direction $encoding\
        --readout $readout --out_prefix $prefix_topup\
        --out_script \
        --topup_options=\"--nthr=$task.cpus\" -f
    sh topup.sh
    cp corrected_b0s.nii.gz ${prefix}__corrected_b0s.nii.gz

    # QC
    if $run_qc;
    then
        extract_dim=\$(mrinfo ${prefix}__b0_mean.nii.gz -size)
        mrconvert ${prefix}__b0_mean.nii.gz ${prefix}__b0_mean_viz.nii.gz -stride -1,2,3
        mrconvert ${prefix}__rev_b0_mean.nii.gz ${prefix}__rev_b0_mean_viz.nii.gz -stride -1,2,3
        mrconvert ${prefix}__corrected_b0s.nii.gz ${prefix}__corrected_b0s_viz.nii.gz -stride -1,2,3

        # Get the middle slice
        read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"
        coronal_dim=\$((\$coronal_dim / 2))
        axial_dim=\$((\$axial_dim / 2))
        sagittal_dim=\$((\$sagittal_dim / 2))

        fslsplit ${prefix}__corrected_b0s_viz.nii.gz ${prefix}__ -t
        for image in b0_mean_viz rev_b0_mean_viz 0000 0001;
        do
            viz_params="--display_slice_number --display_lr --size 256 256"
            scil_volume_math normalize_max ${prefix}__\${image}.nii.gz ${prefix}__\${image}_norm.nii.gz
            scil_viz_volume_screenshot ${prefix}__\${image}_norm.nii.gz ${prefix}__\${image}_coronal.png \${viz_params} --slices \${coronal_dim} --axis coronal
            scil_viz_volume_screenshot ${prefix}__\${image}_norm.nii.gz ${prefix}__\${image}_axial.png \${viz_params} --slices \${axial_dim} --axis axial
            scil_viz_volume_screenshot ${prefix}__\${image}_norm.nii.gz ${prefix}__\${image}_sagittal.png \${viz_params} --slices \${sagittal_dim} --axis sagittal

            if [ \$image == "b0_mean_viz" ] || [ \$image == "rev_b0_mean_viz" ];
            then
                title="Before"
            else
                title="After"
            fi

            convert +append ${prefix}__\${image}_coronal_slice_\${coronal_dim}.png \
                    ${prefix}__\${image}_axial_slice_\${axial_dim}.png  \
                    ${prefix}__\${image}_sagittal_slice_\${sagittal_dim}.png \
                    ${prefix}__\${image}.png
            convert -annotate +20+230 "\${title}" -fill white -pointsize 30 ${prefix}__\${image}.png ${prefix}__\${image}.png
        done

        convert -delay 10 -loop 0 -morph 10 \
                ${prefix}__b0_mean_viz.png ${prefix}__0000.png ${prefix}__b0_mean_viz.png \
                ${prefix}__b0_topup_mqc.gif

        convert  -delay 10 -loop 0 -morph 10 \
                ${prefix}__rev_b0_mean_viz.png ${prefix}__0001.png ${prefix}__rev_b0_mean_viz.png \
                ${prefix}__rev_b0_topup_mqc.gif
    fi

    rm -rf *png
    rm -rf *norm*

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | grep "Version:" | sed -E 's/.*ImageMagick ([0-9.-]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def prefix_topup = task.ext.prefix_topup ? task.ext.prefix_topup : ""

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    scil_volume_math -h
    scil_dwi_extract_b0 -h
    antsRegistrationSyNQuick.sh
    scil_dwi_prepare_topup_command -h

    touch ${prefix}__corrected_b0s.nii.gz
    touch ${prefix}__rev_b0_warped.nii.gz
    touch ${prefix}__rev_b0_mean.nii.gz
    touch ${prefix}__b0_mean.nii.gz
    touch ${prefix}__rev_b0_topup_mqc.gif
    touch ${prefix}__b0_topup_mqc.gif
    touch ${prefix_topup}_fieldcoef.nii.gz
    touch ${prefix_topup}_movpar.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
    END_VERSIONS
    """
}
