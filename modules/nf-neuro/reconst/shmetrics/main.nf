
process RECONST_SHMETRICS {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
        tuple val(meta), path(sh), path(mask), path(fa), path(md)

    output:
        tuple val(meta), path("*peaks.nii.gz")          , emit: peaks, optional: true
        tuple val(meta), path("*peak_indices.nii.gz")   , emit: peak_indices, optional: true
        tuple val(meta), path("*peak_values.nii.gz")    , emit: peak_values, optional: true
        tuple val(meta), path("*afd_max.nii.gz")        , emit: afd_max, optional: true
        tuple val(meta), path("*afd_total.nii.gz")      , emit: afd_total, optional: true
        tuple val(meta), path("*afd_sum.nii.gz")        , emit: afd_sum, optional: true
        tuple val(meta), path("*nufo.nii.gz")           , emit: nufo, optional: true
        tuple val(meta), path("*ventricles_mask.nii.gz"), emit: vent_mask, optional: true
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def sh_basis = task.ext.sh_basis ? "--sh_basis " + task.ext.sh_basis : ""
    def relative_threshold = task.ext.relative_threshold ? "--rt " + task.ext.relative_threshold : ""
    def fodf_metrics_a_factor = task.ext.fodf_metrics_a_factor ? task.ext.fodf_metrics_a_factor : 2.0
    def fa_threshold = task.ext.fa_threshold ? "--fa_t " + task.ext.fa_threshold : ""
    def md_threshold = task.ext.md_threshold ? "--md_t " + task.ext.md_threshold : ""
    def processes = task.cpus ? "--processes " + task.cpus : ""
    def absolute_peaks = task.ext.absolute_peaks ? "--abs_peaks_and_values" : ""
    def set_mask = mask ? "--mask $mask" : ""

    if ( task.ext.peaks ) peaks = "--peaks ${prefix}__peaks.nii.gz" else peaks = ""
    if ( task.ext.peak_values ) peak_values = "--peak_values ${prefix}__peak_values.nii.gz" else peak_values = ""
    if ( task.ext.peak_indices ) peak_indices = "--peak_indices ${prefix}__peak_indices.nii.gz" else peak_indices = ""
    if ( task.ext.afd_max ) afd_max = "--afd_max ${prefix}__afd_max.nii.gz" else afd_max = ""
    if ( task.ext.afd_total ) afd_total = "--afd_total ${prefix}__afd_total.nii.gz" else afd_total = ""
    if ( task.ext.afd_sum ) afd_sum = "--afd_sum ${prefix}__afd_sum.nii.gz" else afd_sum = ""
    if ( task.ext.nufo ) nufo = "--nufo ${prefix}__nufo.nii.gz" else nufo = ""
    if ( task.ext.ventricles_mask ) vent_mask = "--out_mask ${prefix}__ventricles_mask.nii.gz" else vent_mask = ""

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_fodf_max_in_ventricles $sh $fa $md \
        --max_value_output ventricles_fodf_max_value.txt $sh_basis \
        $fa_threshold $md_threshold $vent_mask -f

    echo "Maximal peak value in ventricle in file : \$(cat ventricles_fodf_max_value.txt)"

    a_factor=$fodf_metrics_a_factor
    v_max=\$(sed -E 's/([+-]?[0-9.]+)[eE]\\+?(-?)([0-9]+)/(\\1*10^\\2\\3)/g' <<<"\$(cat ventricles_fodf_max_value.txt)")

    echo "Maximal peak value in ventricles : \${v_max}"

    a_threshold=\$(echo "scale=10; \${a_factor} * \${v_max}" | bc)
    if (( \$(echo "\${a_threshold} <= 0" | bc -l) )); then
        a_threshold=1E-10
    fi

    echo "Computing fodf metrics with absolute threshold : \${a_threshold}"

    scil_fodf_metrics $sh \
        $set_mask $sh_basis $absolute_peaks \
        $peaks $peak_values $peak_indices \
        $afd_max $afd_total \
        $afd_sum $nufo \
        $relative_threshold --not_all --at \${a_threshold} \
        $processes

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_fodf_max_in_ventricles -h
    scil_fodf_metrics -h

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
