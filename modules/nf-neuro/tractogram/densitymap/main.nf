process TRACTOGRAM_DENSITYMAP {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(tractogram)

    output:
    tuple val(meta), path("*__*.nii.gz"), emit: density_map
    path "versions.yml"                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def binary = task.ext.is_binary ? "--binary" : ""
    def endpoints_only = task.ext.endpoint_only ? "--endpoints_only" : ""

    """
    bname=\$(basename ${tractogram} .trk)
    scil_tractogram_compute_density_map $tractogram ${prefix}__\${bname}.nii.gz ${binary} ${endpoints_only}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    scil_tractogram_compute_density_map -h

    touch ${prefix}__AF_L.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
