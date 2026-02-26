
process RECONST_DTIMETRICS {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(b0mask)

    output:
        tuple val(meta), path("*__ad.nii.gz")                      , emit: ad, optional: true
        tuple val(meta), path("*__evecs.nii.gz")                   , emit: evecs, optional: true
        tuple val(meta), path("*__evecs_v1.nii.gz")                , emit: evecs_v1, optional: true
        tuple val(meta), path("*__evecs_v2.nii.gz")                , emit: evecs_v2, optional: true
        tuple val(meta), path("*__evecs_v3.nii.gz")                , emit: evecs_v3, optional: true
        tuple val(meta), path("*__evals.nii.gz")                   , emit: evals, optional: true
        tuple val(meta), path("*__evals_e1.nii.gz")                , emit: evals_e1, optional: true
        tuple val(meta), path("*__evals_e2.nii.gz")                , emit: evals_e2, optional: true
        tuple val(meta), path("*__evals_e3.nii.gz")                , emit: evals_e3, optional: true
        tuple val(meta), path("*__fa.nii.gz")                      , emit: fa, optional: true
        tuple val(meta), path("*__ga.nii.gz")                      , emit: ga, optional: true
        tuple val(meta), path("*__rgb.nii.gz")                     , emit: rgb, optional: true
        tuple val(meta), path("*__md.nii.gz")                      , emit: md, optional: true
        tuple val(meta), path("*__mode.nii.gz")                    , emit: mode, optional: true
        tuple val(meta), path("*__norm.nii.gz")                    , emit: norm, optional: true
        tuple val(meta), path("*__rd.nii.gz")                      , emit: rd, optional: true
        tuple val(meta), path("*__tensor.nii.gz")                  , emit: tensor, optional: true
        tuple val(meta), path("*__nonphysical.nii.gz")             , emit: nonphysical, optional: true
        tuple val(meta), path("*__pulsation_std_dwi.nii.gz")       , emit: pulsation_std_dwi, optional: true
        tuple val(meta), path("*__pulsation_std_b0.nii.gz")        , emit: pulsation_std_b0, optional: true
        tuple val(meta), path("*__residual.nii.gz")                , emit: residual, optional: true
        tuple val(meta), path("*__residual_iqr_residuals.npy")     , emit: residual_iqr_residuals, optional: true
        tuple val(meta), path("*__residual_mean_residuals.npy")    , emit: residual_mean_residuals, optional: true
        tuple val(meta), path("*__residual_q1_residuals.npy")      , emit: residual_q1_residuals, optional: true
        tuple val(meta), path("*__residual_q3_residuals.npy")      , emit: residual_q3_residuals, optional: true
        tuple val(meta), path("*__residual_residuals_stats.png")   , emit: residual_residuals_stats, optional: true
        tuple val(meta), path("*__residual_std_residuals.npy")     , emit: residual_std_residuals, optional: true
        tuple val(meta), path("*__dti_mqc.png")                    , emit: mqc   , optional: true
        path "versions.yml"                                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? "--tolerance " + task.ext.dwi_shell_tolerance : ""
    def max_dti_shell_value = task.ext.max_dti_shell_value ?: 1500
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: 10
    def b0_threshold = task.ext.b0_thr_extract_b0 ? "--b0_threshold $task.ext.b0_thr_extract_b0" : ""
    def dti_shells = task.ext.dti_shells ?: "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v<=$max_dti_shell_value|| v<=$b0_thr_extract_b0)print v}' | sort | uniq)"
    def run_qc = task.ext.run_qc ?: false

    if ( b0mask ) args += " --mask $b0mask"
    if ( task.ext.ad ) args += " --ad ${prefix}__ad.nii.gz"
    if ( task.ext.evecs ) args += " --evecs ${prefix}__evecs.nii.gz"
    if ( task.ext.evals ) args += " --evals ${prefix}__evals.nii.gz"
    if ( task.ext.fa ) args += " --fa ${prefix}__fa.nii.gz"
    if ( task.ext.ga ) args += " --ga ${prefix}__ga.nii.gz"
    if ( task.ext.rgb ) args += " --rgb ${prefix}__rgb.nii.gz"
    if ( task.ext.md ) args += " --md ${prefix}__md.nii.gz"
    if ( task.ext.mode ) args += " --mode ${prefix}__mode.nii.gz"
    if ( task.ext.norm ) args += " --norm ${prefix}__norm.nii.gz"
    if ( task.ext.rd ) args += " --rd ${prefix}__rd.nii.gz"
    if ( task.ext.tensor ) args += " --tensor ${prefix}__tensor.nii.gz"
    if ( task.ext.nonphysical ) args += " --non-physical ${prefix}__nonphysical.nii.gz"
    if ( task.ext.pulsation ) args += " --pulsation ${prefix}__pulsation.nii.gz"
    if ( task.ext.residual ) args += " --residual ${prefix}__residual.nii.gz"

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_shell $dwi $bval $bvec $dti_shells \
                dwi_dti_shells.nii.gz bval_dti_shells bvec_dti_shells \
                $dwi_shell_tolerance -f

    scil_dti_metrics dwi_dti_shells.nii.gz bval_dti_shells bvec_dti_shells \
        --not_all $args $b0_threshold -f

    ransac_metrics=\$(echo "$args" | awk '{for(i=1; i<NF; i++) if (\$i ~ /^--(ad|rd|md)\$/) print \$(i+1)}')
    for metrics in \${ransac_metrics};
    do
        scil_volume_remove_outliers_ransac \${metrics} \${metrics} -f;
    done

    if [ "$run_qc" = true ] && [ "$args" != '' ];
    then
        if [ -f ${prefix}__residual_residuals_stats.png ];
        then
            mv ${prefix}__residual_residuals_stats.png ${prefix}__residual_residuals_stats.png_bk
        fi

        nii_files=\$(echo "$args" | awk '{for(i=1; i<NF; i++) if (\$i ~ /^--(fa|ad|rd|md|rgb|residual)\$/) print \$(i+1)}')

        # Viz 3D images + RGB
        for image in \${nii_files};
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

            # Get the middle slice
            coronal_dim=\$((\$coronal_dim / 2))
            axial_dim=\$((\$axial_dim / 2))
            sagittal_dim=\$((\$sagittal_dim / 2))

            echo \$coronal_dim
            echo \$axial_dim
            echo \$sagittal_dim

            image=\${image/${prefix}__/}
            image=\${image/.nii.gz/}
            mrconvert ${prefix}__\${image}.nii.gz ${prefix}__\${image}_viz.nii.gz -stride -1,2,3
            viz_params="--display_slice_number --display_lr --size 256 256"
            scil_viz_volume_screenshot ${prefix}__\${image}_viz.nii.gz ${prefix}__\${image}_coronal.png \${viz_params} --slices \${coronal_dim} --axis coronal
            scil_viz_volume_screenshot ${prefix}__\${image}_viz.nii.gz ${prefix}__\${image}_axial.png \${viz_params} --slices \${axial_dim} --axis axial
            scil_viz_volume_screenshot ${prefix}__\${image}_viz.nii.gz ${prefix}__\${image}_sagittal.png \${viz_params} --slices \${sagittal_dim} --axis sagittal

            convert +append ${prefix}__\${image}_coronal_slice_\${coronal_dim}.png \
                    ${prefix}__\${image}_axial_slice_\${axial_dim}.png  \
                    ${prefix}__\${image}_sagittal_slice_\${sagittal_dim}.png \
                    ${prefix}__\${image}.png

            convert -annotate +20+230 "\${image}" -fill white -pointsize 30 ${prefix}__\${image}.png ${prefix}__\${image}.png
        done

        rm -rf *slice*
        convert -append *png ${prefix}__dti_mqc.png
        if [ -f ${prefix}__residual_residuals_stats.png_bk ];
        then
            mv ${prefix}__residual_residuals_stats.png_bk ${prefix}__residual_residuals_stats.png
        fi
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv -q -n pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    scil_dwi_extract_shell -h
    scil_dti_metrics -h
    scil_volume_remove_outliers_ransac -h
    convert -h
    mrinfo -h

    touch ${prefix}__ad.nii.gz
    touch ${prefix}__evecs.nii.gz
    touch ${prefix}__evecs_v1.nii.gz
    touch ${prefix}__evecs_v2.nii.gz
    touch ${prefix}__evecs_v3.nii.gz
    touch ${prefix}__evals.nii.gz
    touch ${prefix}__evals_e1.nii.gz
    touch ${prefix}__evals_e2.nii.gz
    touch ${prefix}__evals_e3.nii.gz
    touch ${prefix}__fa.nii.gz
    touch ${prefix}__ga.nii.gz
    touch ${prefix}__rgb.nii.gz
    touch ${prefix}__md.nii.gz
    touch ${prefix}__mode.nii.gz
    touch ${prefix}__norm.nii.gz
    touch ${prefix}__rd.nii.gz
    touch ${prefix}__tensor.nii.gz
    touch ${prefix}__nonphysical.nii.gz
    touch ${prefix}__pulsation_std_dwi.nii.gz
    touch ${prefix}__pulsation_std_b0.nii.gz
    touch ${prefix}__residual.nii.gz
    touch ${prefix}__residual_iqr_residuals.npy
    touch ${prefix}__residual_mean_residuals.npy
    touch ${prefix}__residual_q1_residuals.npy
    touch ${prefix}__residual_q3_residuals.npy
    touch ${prefix}__residual_residuals_stats.png
    touch ${prefix}__residual_std_residuals.npy
    touch ${prefix}__dti_mqc.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv -q -n pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrinfo -version 2>&1 | grep "== mrinfo" | sed -E 's/== mrinfo ([0-9.]+).*/\\1/')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
    END_VERSIONS
    """
}
