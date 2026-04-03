process IMAGE_APPLYMASK {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
        tuple val(meta), path(image), path(mask)

    output:
        tuple val(meta), path("*masked.nii.gz")     , emit: image
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def nthreads_mrtrix = task.ext.single_thread ? "-nthreads 0" : "-nthreads ${task.cpus}"

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    mrcalc $image $mask -mult ${prefix}_masked.nii.gz -force -quiet ${nthreads_mrtrix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}_masked.nii.gz

    mrcalc -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
