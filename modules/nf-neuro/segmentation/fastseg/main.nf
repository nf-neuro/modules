process SEGMENTATION_FASTSEG {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
        tuple val(meta), path(image), path(lesion)

    output:
        tuple val(meta), path("*mask_wm.nii.gz")                , emit: wm_mask
        tuple val(meta), path("*mask_gm.nii.gz")                , emit: gm_mask
        tuple val(meta), path("*mask_csf.nii.gz")               , emit: csf_mask
        tuple val(meta), path("*map_wm.nii.gz")                 , emit: wm_map
        tuple val(meta), path("*map_gm.nii.gz")                 , emit: gm_map
        tuple val(meta), path("*map_csf.nii.gz")                , emit: csf_map
        path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    fast -t 1 -n 3\
        -H 0.1 -I 4 -l 20.0 -g -o t1.nii.gz $image
    scil_volume_math convert t1_seg_2.nii.gz ${prefix}__mask_wm.nii.gz --data_type uint8
    scil_volume_math convert t1_seg_1.nii.gz ${prefix}__mask_gm.nii.gz --data_type uint8
    scil_volume_math convert t1_seg_0.nii.gz ${prefix}__mask_csf.nii.gz --data_type uint8
    mv t1_pve_2.nii.gz ${prefix}__map_wm.nii.gz
    mv t1_pve_1.nii.gz ${prefix}__map_gm.nii.gz
    mv t1_pve_0.nii.gz ${prefix}__map_csf.nii.gz

    if [[ -f "$lesion" ]];
    then
        scil_volume_math union ${prefix}__mask_wm.nii.gz $lesion ${prefix}__mask_wm.nii.gz --data_type uint8 -f
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    fast -h
    scil_volume_math -h

    touch ${prefix}__mask_wm.nii.gz
    touch ${prefix}__mask_gm.nii.gz
    touch ${prefix}__mask_csf.nii.gz
    touch ${prefix}__map_wm.nii.gz
    touch ${prefix}__map_gm.nii.gz
    touch ${prefix}__map_csf.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
    END_VERSIONS
    """
}
