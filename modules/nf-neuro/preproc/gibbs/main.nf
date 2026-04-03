process PREPROC_GIBBS {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(dwi)

    output:
    tuple val(meta), path("*dwi_gibbs_corrected.nii.gz"), emit: dwi
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def nthreads_mrtrix = task.ext.single_thread ? "-nthreads 0" : "-nthreads ${task.cpus}"

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export MRTRIX_RNG_SEED=${task.ext.mrtrix_rng_seed ? task.ext.mrtrix_rng_seed : "1234"}

    mrdegibbs $dwi ${prefix}__dwi_gibbs_corrected.nii.gz ${nthreads_mrtrix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrdegibbs -version 2>&1 | sed -n 's/== mrdegibbs \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mrdegibbs -h

    touch ${prefix}__dwi_gibbs_corrected.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrdegibbs -version 2>&1 | sed -n 's/== mrdegibbs \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
