process SEGMENTATION_FASTSEG {
    tag "$meta.id"
    label 'process_single'

    container 'scilus/scilus:2.2.2'

    input:
        tuple val(meta), path(image), path(lesion), val(image_type)

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
    def image_type_int = image_type ? image_type.toInteger() : 1
    def image_type_flag = image_type ? "-t $image_type_int" : ""
    def allowed_image_types = [1, 2, 3]
    if ( !allowed_image_types.contains(image_type_int) ) {
        error "Invalid image type '${image_type_int}'. Allowed types are: 1 (for T1), 2 (for T2), 3 (for PD)."
    }
    def nb_class_int = task.ext.nb_class ? task.ext.nb_class.toInteger() : 3
    def nb_class = task.ext.nb_class ? "-n $nb_class_int" : "-n 3"
    def allowed_n_classes = [2, 3, 4]
    if ( !allowed_n_classes.contains(nb_class_int) ) {
        error "Invalid number of classes '${nb_class_int}'. Allowed values are 2, 3 and 4."
    }

    // Fast produces segmentation that are indexed from 0 to nb_class - 1.
    // To support all possible configs of nb_class and image type, we need
    // a mapping from the index to GM, WM and CSF.
    def image_type_index = [
        1: [ // For T1 images, depending on the number of classes
            2: [wm: 1, gm: 1, csf: 0], // n=2: WM and GM are the same class, CSF is 0
            3: [wm: 2, gm: 1, csf: 0], // n=3: All separated
            4: [wm: 3, gm: 2, csf: 0], // n=4: Additional class for hyperintense lesions based on FSL docs
        ],
        2: [ // For T2 images
            2: [wm: 1, gm: 0, csf: 0], // n=2: WM is 1 and CSF/GM are 0
            3: [wm: 2, gm: 0, csf: 1], // n=3: All separated
            4: [wm: 3, gm: 1, csf: 2], // n=4: Additional class for dark non-brain matter based on FSL docs
        ],
        3: [ // For PD images
            2: [wm: 0, gm: 1, csf: 1], // n=2: GM and CSF are the same class, WM is 0
            3: [wm: 1, gm: 2, csf: 0], // n=3: All separated
            4: [wm: 1, gm: 2, csf: 0], // n=4: Same as n=3, but with an additional class (dark non-brain matter based on FSL docs)
        ],
    ]
    def class_idx = image_type_index[image_type_int][nb_class_int]
    if ( class_idx.wm < 0 || class_idx.wm >= (nb_class_int) ) {
        error "Invalid wm_class '${class_idx.wm}'. Class index must be between 0 and ${nb_class_int - 1}."
    }
    if ( class_idx.gm < 0 || class_idx.gm >= (nb_class_int) ) {
        error "Invalid gm_class '${class_idx.gm}'. Class index must be between 0 and ${nb_class_int - 1}."
    }
    if ( class_idx.csf < 0 || class_idx.csf >= (nb_class_int) ) {
        error "Invalid csf_class '${class_idx.csf}'. Class index must be between 0 and ${nb_class_int - 1}."
    }

    def nb_iter = task.ext.nb_iter ? "-I $task.ext.nb_iter" : ""
    def low_pass = task.ext.low_pass ? "-l $task.ext.low_pass" : ""
    def fhard = task.ext.fhard ? "-f $task.ext.fhard" : ""
    def hyper = task.ext.hyper ? "-H $task.ext.hyper" : ""
    def nobias = task.ext.nobias ? "-N" : ""
    def init = task.ext.init ? "-W $task.ext.init" : ""
    def mixel = task.ext.mixel ? "-R $task.ext.mixel" : ""
    def fixed = task.ext.fixed ? "-O $task.ext.fixed" : ""

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    fast -g -o ${prefix} \
        $image_type_flag \
        $nb_class \
        $hyper \
        $nb_iter \
        $low_pass \
        $fhard \
        $nobias \
        $init \
        $mixel \
        $fixed \
        $image

    scil_volume_math convert ${prefix}_seg_${class_idx.wm}.nii.gz ${prefix}__mask_wm.nii.gz --data_type uint8
    scil_volume_math convert ${prefix}_seg_${class_idx.gm}.nii.gz ${prefix}__mask_gm.nii.gz --data_type uint8
    scil_volume_math convert ${prefix}_seg_${class_idx.csf}.nii.gz ${prefix}__mask_csf.nii.gz --data_type uint8
    cp ${prefix}_pve_${class_idx.wm}.nii.gz ${prefix}__map_wm.nii.gz
    cp ${prefix}_pve_${class_idx.gm}.nii.gz ${prefix}__map_gm.nii.gz
    cp ${prefix}_pve_${class_idx.csf}.nii.gz ${prefix}__map_csf.nii.gz

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
