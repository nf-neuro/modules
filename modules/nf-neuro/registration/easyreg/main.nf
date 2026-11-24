

process REGISTRATION_EASYREG {
    tag "$meta.id"
    label 'process_high'

    container "freesurfer/freesurfer:7.4.1"

    input:
    tuple val(meta), path(fixed_image), path(moving_image), path(fixed_segmentation), path(moving_segmentation)

    output:
    tuple val(meta), path("*_warped.nii.gz")                        , emit: image_warped
    tuple val(meta), path("*_warped_reference.nii.gz")              , emit: fixed_warped
    tuple val(meta), path("*_forward0_warp.nii.gz")                 , emit: forward_warp, optional: true
    tuple val(meta), path("*_backward0_warp.nii.gz")                , emit: backward_warp, optional: true
    tuple val(meta), path("*_fixed_segmentation.nii.gz")            , emit: fixed_segmentation, optional: true
    tuple val(meta), path("*_moving_segmentation.nii.gz")           , emit: moving_segmentation, optional: true
    path "versions.yml"                                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? "${task.ext.suffix}_warped" : "warped"
    def affine_only = task.ext.affine_only ? "--affine_only " : ""
    def nthreads = task.ext.single_thread ? 1 : task.cpus
    // SynthSeg segmentations are computed by EasyReg only when not provided, in their own image space
    fixed_segmentation = "--ref_seg ${fixed_segmentation ?: "${prefix}_fixed_segmentation.nii.gz" }"
    moving_segmentation = "--flo_seg ${moving_segmentation ?: "${prefix}_moving_segmentation.nii.gz" }"
    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    moving_base=\$(basename "${moving_image}")
    ext=\${moving_base#*.}
    moving_id=\${moving_base%.\${ext}}
    moving_id=\${moving_id#${prefix}_*}

    mri_easyreg --ref $fixed_image \
        --flo $moving_image \
        --flo_reg ${prefix}_\${moving_id}_${suffix}.nii.gz \
        --ref_reg ${prefix}_${suffix}_reference.nii.gz \
        --fwd_field ${prefix}_forward0_warp.nii.gz \
        --bak_field ${prefix}_backward0_warp.nii.gz \
        $fixed_segmentation $moving_segmentation \
        --threads $nthreads $affine_only

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: 7.4.1
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? "${task.ext.suffix}_warped" : "warped"

    """
    mri_easyreg -h

    moving_base=\$(basename "${moving_image}")
    ext=\${moving_base#*.}
    moving_id=\${moving_base%.\${ext}}
    moving_id=\${moving_id#${prefix}_*}

    touch ${prefix}_\${moving_id}_${suffix}.nii.gz
    touch ${prefix}_${suffix}_reference.nii.gz
    ${fixed_segmentation ? "" : "touch ${prefix}_fixed_segmentation.nii.gz"}
    ${moving_segmentation ? "" : "touch ${prefix}_moving_segmentation.nii.gz"}
    touch ${prefix}_forward0_warp.nii.gz
    touch ${prefix}_backward0_warp.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: 7.4.1
    END_VERSIONS
    """
}
