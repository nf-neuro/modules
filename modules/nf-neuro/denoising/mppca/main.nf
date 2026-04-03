
process DENOISING_MPPCA {
    tag "$meta.id"
    label 'process_medium'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(dwi), path(mask)

    output:
    tuple val(meta), path("*_dwi_denoised.nii.gz")  , emit: image
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def extent = task.ext.extent ? "-extent " + task.ext.extent : ""
    def mask_opt = task.ext.mask ? "-mask $mask" : ""
    def nthreads_mrtrix = task.ext.single_thread ? "-nthreads 0" : "-nthreads ${task.cpus}"

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export MRTRIX_RNG_SEED=${task.ext.mrtrix_rng_seed ? task.ext.mrtrix_rng_seed : "1234"}

    dwidenoise $dwi ${prefix}_dwi_denoised.nii.gz $extent ${nthreads_mrtrix} ${mask_opt}
    mrcalc ${prefix}_dwi_denoised.nii.gz 0 -gt ${prefix}_dwi_denoised.nii.gz 0 \
        -if ${prefix}_dwi_denoised.nii.gz -force ${nthreads_mrtrix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    dwidenoise -h
    mrcalc -h

    touch ${prefix}_dwi_denoised.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
