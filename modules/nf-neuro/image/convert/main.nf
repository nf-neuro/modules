process IMAGE_CONVERT {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(image)

    output:
    tuple val(meta), path("*_converted.nii.gz") , emit: image
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def datatype = task.ext.datatype ? "-datatype ${task.ext.datatype}" : '' // REQUIRED.
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_${task.ext.datatype}_converted" : "${task.ext.datatype}_converted"

    """
    mrconvert $image ${prefix}_${suffix}.nii.gz $datatype

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrconvert: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_${task.ext.datatype}_converted" : "${task.ext.datatype}_converted"

    """
    touch ${prefix}_${suffix}.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrconvert: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
