process SEGMENTATION_SAMSEG {
    tag "$meta.id"
    label 'process_high'
    label 'process_high_memory'

    container "freesurfer/freesurfer:7.4.1"

    input:
    tuple val(meta), path(t1), path(flair), path(fs_license)

    output:
    tuple val(meta), path("*__space-t1_label-WMlesion_desc-samseg_mask.nii.gz")    , emit: lesion_mask
    tuple val(meta), path("*__space-t1_seg-WMlesion_desc-samseg_probseg.nii.gz")   , emit: lesion_probseg
    tuple val(meta), path("*__space-t1_desc-samseg_dseg.nii.gz")                   , emit: samseg_dseg
    path "versions.yml"                                                            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def nthreads = task.ext.single_thread ? 1 : task.cpus
    def lesion_mask_pattern = task.ext.lesion_mask_pattern ?: "0 1"
    def threshold = task.ext.threshold != null ? "--threshold ${task.ext.threshold}" : ""
    def random_seed = task.ext.random_seed != null ? "--random-seed ${task.ext.random_seed}" : ""

    """
    export OMP_NUM_THREADS=$nthreads
    export MKL_NUM_THREADS=$nthreads
    export OPENBLAS_NUM_THREADS=$nthreads
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$nthreads
    export FS_LICENSE=\$PWD/$fs_license

    # --save-posteriors takes structure-name substrings, not label numbers.
    # Label 99 (lesions) is named "Lesions" in the samseg atlas, written to posteriors/Lesions.mgz.
    run_samseg \
        --input $t1 $flair \
        --output samseg_out \
        --lesion \
        --lesion-mask-pattern $lesion_mask_pattern \
        --pallidum-separate \
        --save-posteriors Lesions \
        --threads $nthreads \
        $threshold \
        $random_seed

    if [[ ! -f samseg_out/seg.mgz ]]; then
        echo "Error: SAMSEG output seg.mgz is missing." >&2
        exit 1
    fi

    if [[ ! -f samseg_out/posteriors/Lesions.mgz ]]; then
        echo "Error: SAMSEG lesion posterior is missing. Content of samseg_out/posteriors:" >&2
        ls samseg_out/posteriors >&2 || true
        exit 1
    fi

    mri_convert samseg_out/seg.mgz ${prefix}__space-t1_desc-samseg_dseg.nii.gz

    mri_binarize --i samseg_out/seg.mgz --match 99 \
        --o ${prefix}__space-t1_label-WMlesion_desc-samseg_mask.nii.gz
    mri_convert -i ${prefix}__space-t1_label-WMlesion_desc-samseg_mask.nii.gz --out_data_type uchar \
        -o ${prefix}__space-t1_label-WMlesion_desc-samseg_mask.nii.gz

    mri_convert samseg_out/posteriors/Lesions.mgz ${prefix}__space-t1_seg-WMlesion_desc-samseg_probseg.nii.gz
    rm -rf samseg_out

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9.]+).*/\\1/')
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

    run_samseg --help
    mri_binarize --help
    mri_convert --help

    touch ${prefix}__space-t1_label-WMlesion_desc-samseg_mask.nii.gz
    touch ${prefix}__space-t1_seg-WMlesion_desc-samseg_probseg.nii.gz
    touch ${prefix}__space-t1_desc-samseg_dseg.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9.]+).*/\\1/')
    END_VERSIONS
    """
}
