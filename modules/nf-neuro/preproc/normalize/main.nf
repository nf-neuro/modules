process PREPROC_NORMALIZE {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec), path(mask)

    output:
    tuple val(meta), path("*dwi_normalized.nii.gz")     , emit: dwi
    tuple val(meta), path("*fa_wm_mask.nii.gz")         , emit: mask
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? "--tolerance $task.ext.dwi_shell_tolerance" : ""
    def fa_mask_threshold = task.ext.fa_mask_threshold ? "-abs $task.ext.fa_mask_threshold": ""
    def max_dti_shell_value = task.ext.max_dti_shell_value ?: "1600"
    def prefix = task.ext.prefix ?: "${meta.id}"
    def dti_info = task.ext.dti_shells ?: "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v<=$max_dti_shell_value)print v}' | sort | uniq)"

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OMP_NUM_THREADS=$task.cpus
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_shell $dwi $bval $bvec $dti_info dwi_dti.nii.gz \
        bval_dti bvec_dti $dwi_shell_tolerance

    scil_dti_metrics dwi_dti.nii.gz bval_dti bvec_dti --mask $mask \
        --not_all --fa fa.nii.gz --skip_b0_check

    mrthreshold fa.nii.gz ${prefix}_fa_wm_mask.nii.gz $fa_mask_threshold \
        -nthreads $task.cpus

    dwinormalise individual $dwi ${prefix}_fa_wm_mask.nii.gz \
        ${prefix}__dwi_normalized.nii.gz -fslgrad $bvec $bval -nthreads $task.cpus

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell -h
    scil_dti_metrics -h
    mrthreshold -h
    dwinormalise -h

    touch ${prefix}__dwi_normalized.nii.gz
    touch ${prefix}__fa_wm_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
