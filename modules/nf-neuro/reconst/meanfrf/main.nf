

process RECONST_MEANFRF {
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(prefix), path(frf_list)

    output:
        tuple val(prefix), path("*mean_frf.txt")         , emit: meanfrf
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_frf_mean $frf_list ${prefix}_mean_frf.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    """
    scil_frf_mean -h

    touch ${prefix}_mean_frf.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
