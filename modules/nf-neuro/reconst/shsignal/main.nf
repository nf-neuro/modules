process RECONST_SHSIGNAL {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask) /* optional, value = [] */

    output:
        tuple val(meta), path("*__dwi_sh.nii.gz")   , emit: sh_signal
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def max_shell_bvalue = task.ext.max_shell_bvalue ?: 1500
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: 10
    def b0_threshold = task.ext.b0_thr_extract_b0 ? "--b0_threshold $task.ext.b0_thr_extract_b0" : ""
    def shell_to_fit = task.ext.shell_to_fit ?: "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v<=$max_shell_bvalue|| v<=$b0_thr_extract_b0)print v}' | sort | uniq)"
    def sh_order = task.ext.sh_order ? "--sh_order $task.ext.sh_order" : ""
    def sh_basis = task.ext.sh_basis ? "--sh_basis $task.ext.sh_basis" : ""
    def smoothing = task.ext.smoothing ? "--smooth $task.ext.smoothing" : ""
    def attenuation_only = task.ext.fit_attenuation_only ? "--use_attenuation" : ""

    if ( mask ) args += " --mask $mask"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_shell $dwi $bval $bvec $shell_to_fit \
        dwi_sh_shells.nii.gz bval_sh_shells bvec_sh_shells -f

    scil_dwi_to_sh dwi_sh_shells.nii.gz bval_sh_shells bvec_sh_shells \
        ${prefix}__dwi_sh.nii.gz \
        $sh_order $sh_basis $smoothing \
        $attenuation_only $b0_threshold $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell -h
    scil_dwi_to_sh -h

    touch ${prefix}__dwi_sh.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
