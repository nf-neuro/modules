process SEGMENTATION_WMHSYNTHSEG {
    tag "$meta.id"
    label 'process_high'
    memory { 16.GB * task.attempt }

    container "stanislasthoumyre/wmh-synthseg-minimal:1.0.0"

    input:
    tuple val(meta), path(flair)

    output:
    tuple val(meta), path("*_wmh-synthseg_binary.nii.gz")   , emit: binary_mask
    tuple val(meta), path("*_wmh-synthseg_prob.nii.gz")     , emit: probability_map
    path "versions.yml"                                     , emit: versions


    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix      = task.ext.prefix ?: "${meta.id}"
    def label_id    = task.ext.label_id ?: 77
    def use_gpu     = task.ext.gpu
    def device_args = use_gpu ? "--device cuda " : "--device cpu --threads 4"
    def crop        = task.ext.crop ? "--crop " : ""
    """
    set +u
    export FREESURFER_HOME=/usr/local/freesurfer
    export HOME="\$(pwd)"
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"
    source /usr/local/freesurfer/SetUpFreeSurfer.sh
    set -u

    export PATH=/usr/local/freesurfer/python/bin:\${PATH}

    mri_WMHsynthseg --i ${flair} \
                    --o multiclass.nii.gz \
                    --save_lesion_probabilities \
                    ${device_args} \
                    ${crop}

    fspython /usr/local/freesurfer/bin/conform_synthseg.py --input multiclass.nii.gz --ref ${flair} \
             --output ${prefix}_wmh-synthseg_binary.nii.gz --label_id ${label_id}

    fspython /usr/local/freesurfer/bin/conform_synthseg.py --input multiclass.lesion_probs.nii.gz \
             --ref ${flair} --output ${prefix}_wmh-synthseg_prob.nii.gz --continuous

    rm -f multiclass.nii.gz multiclass.lesion_probs.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Freesurfer: \$(cat /usr/local/freesurfer/build-stamp.txt | grep -oP '\\d+\\.\\d+\\.\\d+' | head -1)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mri_WMHsynthseg -h || true

    fspython /usr/local/freesurfer/bin/conform_synthseg.py -h || true

    touch ${prefix}_wmh-synthseg_binary.nii.gz
    touch ${prefix}_wmh-synthseg_prob.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Freesurfer: \$(cat /usr/local/freesurfer/build-stamp.txt | grep -oP '\\d+\\.\\d+\\.\\d+' | head -1)
    END_VERSIONS
    """
}
