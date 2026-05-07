process IMAGE_ANTSMATH{
    tag "$meta.id"
    label 'process_medium'

    container "scilus/scilus:2.2.2"

    input:
        tuple val(meta), path(candidate_labels, arity: '2..*')

    output:
        tuple val(meta), path("*_majorityvote.nii.gz"), emit: label
        path "versions.yml",                            emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    ImageMath 3 ${prefix}_majorityvote.nii.gz MajorityVoting $candidate_labels

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    antsRegistration --version

    touch ${prefix}_majorityvote.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
    END_VERSIONS
    """
}
