
process RECONST_FODF {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask), path(fa), path(md), path(wm_frf), path(gm_frf), path(csf_frf)

    output:
        tuple val(meta), path("*__fodf.nii.gz")           , emit: fodf, optional: true
        tuple val(meta), path("*__wm_fodf.nii.gz")        , emit: wm_fodf, optional: true
        tuple val(meta), path("*__gm_fodf.nii.gz")        , emit: gm_fodf, optional: true
        tuple val(meta), path("*__csf_fodf.nii.gz")       , emit: csf_fodf, optional: true
        tuple val(meta), path("*__vf.nii.gz")             , emit: vf, optional: true
        tuple val(meta), path("*__vf_rgb.nii.gz")         , emit: vf_rgb, optional: true
        tuple val(meta), path("*__peaks.nii.gz")          , emit: peaks, optional: true
        tuple val(meta), path("*__peak_values.nii.gz")    , emit: peak_values, optional: true
        tuple val(meta), path("*__peak_indices.nii.gz")   , emit: peak_indices, optional: true
        tuple val(meta), path("*__afd_max.nii.gz")        , emit: afd_max, optional: true
        tuple val(meta), path("*__afd_total.nii.gz")      , emit: afd_total, optional: true
        tuple val(meta), path("*__afd_sum.nii.gz")        , emit: afd_sum, optional: true
        tuple val(meta), path("*__nufo.nii.gz")           , emit: nufo, optional: true
        tuple val(meta), path("*__ventricles_mask.nii.gz"), emit: vent_mask, optional: true
        path "versions.yml"                               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? "--tolerance " + task.ext.dwi_shell_tolerance : ""
    def min_fodf_shell_value = task.ext.min_fodf_shell_value ?: 100     /* Default value for min_fodf_shell_value */
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: 10        /* Default value for b0_thr_extract_b0 */
    def fodf_shells = task.ext.fodf_shells ? "0 " + task.ext.fodf_shells : "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v>=$min_fodf_shell_value|| v<=$b0_thr_extract_b0)print v}' | sort | uniq)"
    def sh_order = task.ext.sh_order ? "--sh_order " + task.ext.sh_order : ""
    def sh_basis = task.ext.sh_basis ? "--sh_basis " + task.ext.sh_basis : ""
    def set_method = task.ext.method ? task.ext.method : "ssst"
    def processes = task.cpus > 1 ? "--processes " + task.cpus : ""
    def set_mask = mask ? "--mask $mask" : ""
    def relative_threshold = task.ext.relative_threshold ? "--rt " + task.ext.relative_threshold : ""
    def fodf_metrics_a_factor = task.ext.fodf_metrics_a_factor ? task.ext.fodf_metrics_a_factor : 2.0
    def fa_threshold = task.ext.fa_threshold ? "--fa_t " + task.ext.fa_threshold : ""
    def md_threshold = task.ext.md_threshold ? "--md_t " + task.ext.md_threshold : ""
    def absolute_peaks = task.ext.absolute_peaks ? "--abs_peaks_and_values" : ""

    /* if (set_method != "ssst_fodf" || set_method != "msmt_fodf") error "ERROR";*/
    if ( task.ext.wm_fodf ) wm_fodf = "--wm_out_fODF ${prefix}__wm_fodf.nii.gz" else wm_fodf = ""
    if ( task.ext.gm_fodf ) gm_fodf = "--gm_out_fODF ${prefix}__gm_fodf.nii.gz" else gm_fodf = ""
    if ( task.ext.csf_fodf ) csf_fodf = "--csf_out_fODF ${prefix}__csf_fodf.nii.gz" else csf_fodf = ""
    if ( task.ext.vf) vf = "--vf ${prefix}__vf.nii.gz" else vf = ""
    if ( task.ext.vf_rgb) vf_rgb = "--vf_rgb ${prefix}__vf_rgb.nii.gz" else vf_rgb = ""

    if ( task.ext.peaks ) peaks = "--peaks ${prefix}__peaks.nii.gz" else peaks = ""
    if ( task.ext.peak_values ) peak_values = "--peak_values ${prefix}__peak_values.nii.gz" else peak_values = ""
    if ( task.ext.peak_indices ) peak_indices = "--peak_indices ${prefix}__peak_indices.nii.gz" else peak_indices = ""
    if ( task.ext.afd_max ) afd_max = "--afd_max ${prefix}__afd_max.nii.gz" else afd_max = ""
    if ( task.ext.afd_total ) afd_total = "--afd_total ${prefix}__afd_total.nii.gz" else afd_total = ""
    if ( task.ext.afd_sum ) afd_sum = "--afd_sum ${prefix}__afd_sum.nii.gz" else afd_sum = ""
    if ( task.ext.nufo ) nufo = "--nufo ${prefix}__nufo.nii.gz" else nufo = ""
    if ( task.ext.ventricles_mask ) vent_mask = "--out_mask ${prefix}__ventricles_mask.nii.gz" else vent_mask = ""

    def run_fodf_metrics = [
        task.ext.peaks, task.ext.peak_values, task.ext.peak_indices, task.ext.afd_max,
        task.ext.afd_sum, task.ext.afd_total, task.ext.nufo
    ].any()

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_shell $dwi $bval $bvec $fodf_shells \
        dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells \
        $dwi_shell_tolerance -f

    if [ "$set_method" = "ssst" ]
    then

        scil_fodf_ssst dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells $wm_frf ${prefix}__fodf.nii.gz \
            $sh_order $sh_basis --b0_threshold $b0_thr_extract_b0 \
            $set_mask $processes

    elif [ "$set_method" = "msmt" ]
    then

        scil_fodf_msmt dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells \
            $wm_frf $gm_frf $csf_frf \
            $sh_order $sh_basis $set_mask $processes $dwi_shell_tolerance \
            --not_all $wm_fodf $gm_fodf $csf_fodf $vf $vf_rgb

        cp ${prefix}__wm_fodf.nii.gz ${prefix}__fodf.nii.gz

    fi

    if $run_fodf_metrics
    then

        scil_fodf_max_in_ventricles ${prefix}__fodf.nii.gz $fa $md \
        --max_value_output ventricles_fodf_max_value.txt $sh_basis \
        $fa_threshold $md_threshold $vent_mask -f

        echo "Maximal peak value in ventricle in file : \$(cat ventricles_fodf_max_value.txt)"

        a_factor=$fodf_metrics_a_factor
        v_max=\$(sed -E 's/([+-]?[0-9.]+)[eE]\\+?(-?)([0-9]+)/(\\1*10^\\2\\3)/g' <<<"\$(cat ventricles_fodf_max_value.txt)")

        echo "Maximal peak value in ventricles : \${v_max}"
        result=\$(awk "BEGIN {result = \${a_factor} * \${v_max}; if (result <= 0) result = 1e-10; print result}")
        a_threshold=\$(printf "%.10g" \$result)

        echo "Computing fodf metrics with absolute threshold : \${a_threshold}"

        scil_fodf_metrics ${prefix}__fodf.nii.gz \
            $set_mask $sh_basis $absolute_peaks \
            $peaks $peak_values $peak_indices \
            $afd_max $afd_total \
            $afd_sum $nufo $processes \
            $relative_threshold --not_all --at \${a_threshold}
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell -h
    scil_fodf_ssst -h
    scil_fodf_msmt -h
    scil_fodf_max_in_ventricles -h
    scil_fodf_metrics -h

    touch ${prefix}__fodf.nii.gz
    touch ${prefix}__wm_fodf.nii.gz
    touch ${prefix}__gm_fodf.nii.gz
    touch ${prefix}__csf_fodf.nii.gz
    touch ${prefix}__vf.nii.gz
    touch ${prefix}__vf_rgb.nii.gz
    touch ${prefix}__peaks.nii.gz
    touch ${prefix}__peak_values.nii.gz
    touch ${prefix}__peak_indices.nii.gz
    touch ${prefix}__afd_max.nii.gz
    touch ${prefix}__afd_total.nii.gz
    touch ${prefix}__afd_sum.nii.gz
    touch ${prefix}__nufo.nii.gz
    touch ${prefix}__ventricles_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
