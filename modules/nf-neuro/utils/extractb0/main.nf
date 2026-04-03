process UTILS_EXTRACTB0 {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.2_cpu"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*_b0*.nii.gz"), emit: b0
    path "versions.yml"                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def extraction_strategy = task.ext.b0_extraction_strategy ? "--$task.ext.b0_extraction_strategy" : "--mean"
    def b0_threshold = task.ext.b0_threshold ? "--b0_threshold $task.ext.b0_threshold" : ""
    def output_series = task.ext.output_series ? "" : "--single-image"

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    scil_dwi_extract_b0 $dwi $bval $bvec ${prefix}_b0.nii.gz \
        $output_series $extraction_strategy $b0_threshold --skip_b0_check

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_b0 -h

    touch ${prefix}_b0.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
