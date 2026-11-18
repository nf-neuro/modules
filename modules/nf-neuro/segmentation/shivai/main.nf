process SEGMENTATION_SHIVAI {
    tag "$meta.id"
    label 'process_medium'

    container 'stanislasthoumyre/shivai:2.0.0'

    input:
        tuple val(meta), path(t1), path(flair), path(swi)

    output:
        tuple val(meta), path("*__pvs_mask.nii.gz")      , emit: pvs_mask     , optional: true
        tuple val(meta), path("*__wmh_mask.nii.gz")      , emit: wmh_mask     , optional: true
        tuple val(meta), path("*__cmb_mask.nii.gz")      , emit: cmb_mask     , optional: true
        tuple val(meta), path("*__lac_mask.nii.gz")      , emit: lac_mask     , optional: true
        tuple val(meta), path("*__shivai_report.pdf")    , emit: report       , optional: true
        path "versions.yml"                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def prediction  = task.ext.prediction  ?: 'all'
    def input_type  = task.ext.input_type  ?: 'standard'
    def brain_seg   = task.ext.brain_seg   ?: 'shiva'

    def use_cpu             = task.ext.use_cpu             ? '--use_cpu'             : ''
    def inverse_t2          = task.ext.inverse_t2          ? '--inverse_t2'          : ''
    def use_t1              = task.ext.use_t1              ? '--use_t1'              : ''
    def prereg_flair        = task.ext.prereg_flair        ? '--prereg_flair'        : ''
    def preproc_only        = task.ext.preproc_only        ? '--preproc_only'        : ''
    def postproc_only       = task.ext.postproc_only       ? '--postproc_only'       : ''
    def ai_threads      = task.ext.ai_threads      != null ? "--ai_threads ${task.ext.ai_threads}"           : ''   // default: 8
    def percentile      = task.ext.percentile      != null ? "--percentile ${task.ext.percentile}"           : ''   // default: 99
    def threshold       = task.ext.threshold       != null ? "--threshold ${task.ext.threshold}"             : ''   // default: 0.5
    def threshold_pvs   = task.ext.threshold_pvs   != null ? "--threshold_pvs ${task.ext.threshold_pvs}"     : ''   // default: 0.5
    def threshold_wmh   = task.ext.threshold_wmh   != null ? "--threshold_wmh ${task.ext.threshold_wmh}"     : ''   // default: 0.5
    def threshold_cmb   = task.ext.threshold_cmb   != null ? "--threshold_cmb ${task.ext.threshold_cmb}"     : ''   // default: 0.5
    def threshold_lac   = task.ext.threshold_lac   != null ? "--threshold_lac ${task.ext.threshold_lac}"     : ''   // default: 0.5
    def threshold_clusters = task.ext.threshold_clusters != null ? "--threshold_clusters ${task.ext.threshold_clusters}" : ''
    def min_pvs_size    = task.ext.min_pvs_size    != null ? "--min_pvs_size ${task.ext.min_pvs_size}"       : ''   // default: 10 vox
    def min_wmh_size    = task.ext.min_wmh_size    != null ? "--min_wmh_size ${task.ext.min_wmh_size}"       : ''   // default: 10 vox
    def min_cmb_size    = task.ext.min_cmb_size    != null ? "--min_cmb_size ${task.ext.min_cmb_size}"       : ''   // default: 2 vox
    def min_lac_size    = task.ext.min_lac_size    != null ? "--min_lac_size ${task.ext.min_lac_size}"       : ''   // default: 50 vox
    def final_dimensions = task.ext.final_dimensions       ? "--final_dimensions ${task.ext.final_dimensions}" : '' // default: 160 214 176
    def voxels_size      = task.ext.voxels_size            ? "--voxels_size ${task.ext.voxels_size}"         : ''   // default: 1.0 1.0 1.0
    def voxels_tolerance = task.ext.voxels_tolerance       ? "--voxels_tolerance ${task.ext.voxels_tolerance}" : '' // default: 0.01 0.01 0.01
    """

    mkdir -p shiva_input/${prefix}/t1
    cp $t1 shiva_input/${prefix}/t1/T1.nii.gz

    if [[ -f "$flair" ]]; then
        mkdir -p shiva_input/${prefix}/flair
        cp $flair shiva_input/${prefix}/flair/FLAIR.nii.gz
    fi

    if [[ -f "$swi" ]]; then
        mkdir -p shiva_input/${prefix}/swi
        cp $swi shiva_input/${prefix}/swi/SWI.nii.gz
    fi

    shiva \
        --in shiva_input \
        --out shiva_out \
        --prediction $prediction \
        --input_type $input_type \
        --brain_seg $brain_seg \
        --model /opt/shivai/models \
        --config /opt/shivai/shiva_config.yaml \
        $use_cpu \
        $inverse_t2 \
        $use_t1 \
        $prereg_flair \
        $preproc_only \
        $postproc_only \
        $ai_threads \
        $percentile \
        $threshold \
        $threshold_pvs \
        $threshold_wmh \
        $threshold_cmb \
        $threshold_lac \
        $threshold_clusters \
        $min_pvs_size \
        $min_wmh_size \
        $min_cmb_size \
        $min_lac_size \
        $final_dimensions \
        $voxels_size \
        $voxels_tolerance

    find shiva_out/results/segmentations/pvs_segmentation/${prefix} \\
        -name "*labelled*pvs*.nii.gz" \\
        -exec cp {} ${prefix}__pvs_mask.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/segmentations/wmh_segmentation/${prefix} \\
        -name "*labelled*wmh*.nii.gz" \\
        -exec cp {} ${prefix}__wmh_mask.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/segmentations/cmb_segmentation_swi-space/${prefix} \\
        -name "*labelled*cmb*.nii.gz" \\
        -exec cp {} ${prefix}__cmb_mask.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/segmentations/lac_segmentation/${prefix} \\
        -name "*labelled*lac*.nii.gz" \\
        -exec cp {} ${prefix}__lac_mask.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/report/${prefix} \\
        -name "*.pdf" \\
        -exec cp {} ${prefix}__shivai_report.pdf \\; 2>/dev/null || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>&1 | grep -oP '(?<=version: )[0-9.]+')
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

    shiva -h

    touch ${prefix}__pvs_mask.nii.gz
    touch ${prefix}__wmh_mask.nii.gz
    touch ${prefix}__cmb_mask.nii.gz
    touch ${prefix}__lac_mask.nii.gz
    touch ${prefix}__shivai_report.pdf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>&1 | grep -oP '(?<=version: )[0-9.]+')
    END_VERSIONS
    """
}
