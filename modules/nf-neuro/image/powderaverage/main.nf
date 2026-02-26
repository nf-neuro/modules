process IMAGE_POWDERAVERAGE {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(dwi), path(bval), path(mask)

    output:
        tuple val(meta), path("*pwd_avg.nii.gz")    , emit: pwd_avg
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    def b0_thr = task.ext.b0_thr ? "--b0_thr ${task.ext.b0_thr}" : ''
    def shells = task.ext.shells ? "--shells ${task.ext.shells}" : ''
    def shell_thr = task.ext.shell_thr ? "--shell_thr ${task.ext.shell_thr}" : ''

    if ( mask ) args += "--mask ${mask}"

    """
    scil_dwi_powder_average $dwi $bval ${prefix}_pwd_avg.nii.gz \
        $b0_thr $shells $shell_thr $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}_pwd_avg.nii.gz

    scil_dwi_powder_average -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
