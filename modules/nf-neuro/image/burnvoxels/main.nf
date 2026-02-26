process IMAGE_BURNVOXELS {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.1"

    input:
    tuple val(meta), path(masks), path(anat)

    output:
    tuple val(meta), path("*__all.nii.gz")      , emit: all_masks_burned
    tuple val(meta), path("*__*_[0-9]*[0-9].nii.gz") , emit: each_mask_burned
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    String masks_list = masks.join(", ").replace(',', '')
    Integer nb_masks = masks.size()
    """
    # Normalize the anatomy between 0 and 300
    scil_volume_math.py convert ${anat} anat_f32.nii.gz --data_type float32 -f
    scil_volume_math.py normalize_max anat_f32.nii.gz anat_normalize.nii.gz -f
    mrcalc 300 anat_normalize.nii.gz -multiply anat_normalize_300.nii.gz -force

    # Set the step value for be applied to each bundle
    mkdir masks_burned/
    cnt=25
    nb_masks=${nb_masks}
    step=\$(echo 300 \${nb_masks} | awk '{print \$1 / (\$2 - 1)}')

    for m in ${masks_list};
    do
        mname=\${m%%.*}
        mname=\${mname##*__}
        scil_volume_math.py convert \${m} masks_burned/tmp_\${mname}_f32.nii.gz --data_type float32 -f
        mrcalc \${cnt} masks_burned/tmp_\${mname}_f32.nii.gz -multiply masks_burned/mask_\${mname}_\${cnt}.nii.gz -force
        ImageMath 3 ${prefix}__\${mname}_\${cnt}.nii.gz addtozero masks_burned/mask_\${mname}_\${cnt}.nii.gz anat_normalize_300.nii.gz
        rm masks_burned/tmp_\${mname}_f32.nii.gz
        cnt=\$(echo \$cnt \${step} | awk '{print \$1 + \$2}');
    done

    echo $nb_masks
    if [ \$nb_masks -eq 1 ]; then
        mv masks_burned/mask_*.nii.gz mask_all_masks.nii.gz
    else
        scil_volume_math.py addition masks_burned/mask_*.nii.gz mask_all_masks.nii.gz -f
    fi

    ImageMath 3 ${prefix}__all.nii.gz addtozero mask_all_masks.nii.gz anat_normalize_300.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        mrtrix \$(mrcalc -version | grep mrcalc | cut -d" " -f3)
        scilpy: \$(pip list --disable-pip-version-check --no-python-version-warning | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}__all.nii.gz
    touch ${prefix}__AF_L_25.nii.gz
    touch ${prefix}__AF_L_125.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        mrtrix \$(mrcalc -version | grep mrcalc | cut -d" " -f3)
        scilpy: \$(pip list --disable-pip-version-check --no-python-version-warning | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
