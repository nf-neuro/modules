process IMAGE_CONVERTDWI {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(image), path(bval), path(bvec)

    output:
    tuple val(meta), path("*.nii.gz") , emit: image
    tuple val(meta), path("*.bval")   , emit: bval
    tuple val(meta), path("*.bvec")   , emit: bvec
    path "versions.yml"               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def datatype = task.ext.datatype ? "-datatype ${task.ext.datatype}" : ''
    def suffix = task.ext.suffix ? "${task.ext.suffix}" : (task.ext.datatype ? "${task.ext.datatype}_converted" : "converted")
    def strides = task.ext.strides ? "-strides \"${task.ext.strides}\"" : ''

    """
    mrconvert $image ${prefix}_${suffix}.nii.gz $datatype $strides -nthreads 0 \
        -fslgrad ${bvec} ${bval} \
        -export_grad_fsl ${prefix}_${suffix}.bvec ${prefix}_${suffix}.bval -force

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrconvert: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? "${task.ext.suffix}" : (task.ext.datatype ? "${task.ext.datatype}_converted" : "converted")

    """
    touch ${prefix}_${suffix}.nii.gz
    touch ${prefix}_${suffix}.bval
    touch ${prefix}_${suffix}.bvec

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrconvert: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
