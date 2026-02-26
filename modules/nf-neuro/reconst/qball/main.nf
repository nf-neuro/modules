process RECONST_QBALL {
    tag "$meta.id"
    label 'process_medium'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec), path(mask)

    output:
    tuple val(meta), path("*__qball.nii.gz")        , emit: qball, optional: true
    tuple val(meta), path("*__gfa.nii.gz")          , emit: gfa, optional: true
    tuple val(meta), path("*__peaks.nii.gz")        , emit: peaks, optional: true
    tuple val(meta), path("*__peak_indices.nii.gz") , emit: peak_indices, optional: true
    tuple val(meta), path("*__nufo.nii.gz")         , emit: nufo, optional: true
    tuple val(meta), path("*__a_power.nii.gz")      , emit: a_power, optional: true
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def b0_threshold = task.ext.b0_threshold ? " --b0_threshold " + task.ext.b0_threshold : ""
    def sh_order =  task.ext.sh_order ? " --sh_order " + task.ext.sh_order : ""
    def processes = task.cpu ? " --processes " + task.cpu : "--processes 1"

    if ( mask ) args += " --mask $mask"
    if ( task.ext.gfa ) args += " --gfa ${prefix}__gfa.nii.gz"
    if ( task.ext.peaks ) args += " --peaks ${prefix}__peaks.nii.gz"
    if ( task.ext.peak_indices ) args += " --peak_indices ${prefix}__peak_indices.nii.gz"
    if ( task.ext.qball) args += " --sh ${prefix}__qball.nii.gz"
    if ( task.ext.nufo) args += " --nufo ${prefix}__nufo.nii.gz"
    if ( task.ext.a_power) args += " --a_power ${prefix}__a_power.nii.gz"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_qball_metrics $dwi $bval $bvec --not_all $args $b0_threshold $sh_order $processes

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    scil_qball_metrics -h

    touch ${prefix}__gfa.nii.gz
    touch ${prefix}__peaks.nii.gz
    touch ${prefix}__peak_indices.nii.gz
    touch ${prefix}__sh.nii.gz
    touch ${prefix}__nufo.nii.gz
    touch ${prefix}__a_power.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
