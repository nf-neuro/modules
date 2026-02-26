process UTILS_DWISHELL {
    tag "${meta.id}"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*__dwi_sh_shells.nii.gz"), emit: dwi
    tuple val(meta), path("*__bval_sh_shells"), emit: bval
    tuple val(meta), path("*__bvec_sh_shells"), emit: bvec
    tuple val(meta), path("*__out_indices"), emit: out_indices, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def out_indices = task.ext.out_indices ? "--out_indices ${prefix}__out_indices" : ''
    def block_size = task.ext.block_size ? "--block_size ${task.ext.block_size}" : ''
    def tolerance = task.ext.tolerance ? "--tolerance ${task.ext.tolerance}" : ''
    def max_shell_bvalue = task.ext.max_shell_bvalue ?: 1500
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: 10
    def shell_to_fit = task.ext.shell_to_fit ?: "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- ${bval} | awk -F' ' '{v=int(\$1)}{if(v<=${max_shell_bvalue}|| v<=${b0_thr_extract_b0})print v}' | sort | uniq)"
    def force = task.ext.force ? "-f" : ''

    """
    scil_dwi_extract_shell ${dwi} ${bval} ${bvec} ${shell_to_fit} \
        ${prefix}__dwi_sh_shells.nii.gz \
        ${prefix}__bval_sh_shells \
        ${prefix}__bvec_sh_shells \
        ${out_indices} \
        ${block_size} \
        ${tolerance} \
        ${force}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell -h
    touch ${prefix}__dwi_sh_shells.nii.gz
    touch ${prefix}__bval_sh_shells
    touch ${prefix}__bvec_sh_shells

    if [[ ${task.ext.out_indices} ]]; then
        touch ${meta.id}__out_indices
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
