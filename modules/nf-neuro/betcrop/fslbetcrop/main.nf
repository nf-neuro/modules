
process BETCROP_FSLBETCROP {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
        tuple val(meta), path(image), path(bval), path(bvec)

    output:
        tuple val(meta), path("*_bet.nii.gz")            , emit: image
        tuple val(meta), path("*_bet_mask.nii.gz")       , emit: mask
        tuple val(meta), path("*_boundingBox.pkl")       , emit: bbox , optional: true
        path "versions.yml"                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def b0_thr = task.ext.b0_thr ? "--b0_threshold " + task.ext.b0_thr : ""
    def bet_f = task.ext.bet_f ? "-f " + task.ext.bet_f : ""
    def size_dil = task.ext.size_dil ? task.ext.size_dil : ""
    def crop = task.ext.crop == null ?: task.ext.crop as Boolean
    def dilate = task.ext.dilate == null ?: task.ext.dilate as Boolean

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    if [[ -f "$bval" ]]
    then
        scil_dwi_extract_b0 $image $bval $bvec ${prefix}__b0.nii.gz --mean \
            $b0_thr --skip_b0_check

        bet ${prefix}__b0.nii.gz ${prefix}__image_bet.nii.gz -m -R $bet_f
        scil_volume_math convert ${prefix}__image_bet_mask.nii.gz ${prefix}__image_bet_mask.nii.gz --data_type uint8 -f
        mrcalc $image ${prefix}__image_bet_mask.nii.gz -mult ${prefix}__image_bet.nii.gz -quiet -nthreads 1 -force
    else
        bet $image ${prefix}__image_bet.nii.gz -m -R $bet_f
        scil_volume_math convert ${prefix}__image_bet_mask.nii.gz ${prefix}__image_bet_mask.nii.gz --data_type uint8 -f
    fi

    if [ "$crop" = "true" ];
    then
        scil_volume_crop ${prefix}__image_bet.nii.gz ${prefix}__image_bet.nii.gz -f \
            --output_bbox ${prefix}__image_boundingBox.pkl
        scil_volume_crop ${prefix}__image_bet_mask.nii.gz ${prefix}__image_bet_mask.nii.gz -f\
            --input_bbox ${prefix}__image_boundingBox.pkl
        scil_volume_math convert ${prefix}__image_bet_mask.nii.gz ${prefix}__image_bet_mask.nii.gz \
            --data_type uint8 -f
    fi

    if [ "$dilate" = "true" ];
    then
        scil_volume_math dilation ${prefix}__image_bet_mask.nii.gz $size_dil ${prefix}__image_bet_mask.nii.gz --data_type uint8 -f
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
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

    bet
    scil_dwi_extract_b0 -h
    scil_volume_math -h
    mrcalc -h
    scil_volume_crop -h

    touch ${prefix}__image_bet.nii.gz
    touch ${prefix}__image_bet_mask.nii.gz
    touch ${prefix}__image_boundingBox.pkl

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
    END_VERSIONS
    """
}
