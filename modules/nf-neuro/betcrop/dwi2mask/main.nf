
process BETCROP_DWI2MASK {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*_dwi_mask.nii.gz")  , emit: mask
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def nthreads_mrtrix = task.ext.single_thread ? "-nthreads 0" : "-nthreads ${task.cpus}"

    """
    export MRTRIX_RNG_SEED=${task.ext.mrtrix_rng_seed ? task.ext.mrtrix_rng_seed : "1234"}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    dwi2mask $dwi ${prefix}_dwi_mask.nii.gz -fslgrad ${bvec} ${bval} ${nthreads_mrtrix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(dwi2mask -version 2>&1 | sed -n 's/== dwi2mask \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    export MRTRIX_RNG_SEED=${task.ext.mrtrix_rng_seed ? task.ext.mrtrix_rng_seed : "1234"}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    dwi2mask -h

    touch ${prefix}_dwi_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(dwi2mask -version 2>&1 | sed -n 's/== dwi2mask \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
