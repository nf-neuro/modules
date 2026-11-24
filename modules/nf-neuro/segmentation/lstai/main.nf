process SEGMENTATION_LSTAI {
    tag "$meta.id"
    label 'process_high'
    label 'process_high_memory'

    container "${ task.ext.gpu ?
        "jqmcginnis/lst-ai:v2.0.0rc1" :
        "jqmcginnis/lst-ai:v2.0.0rc1-cpu"}"
    containerOptions((workflow.containerEngine == 'docker') ? '--entrypoint "" --user $(id -u):$(id -g)' : '')

    input:
    tuple val(meta), path(t1), path(flair)

    output:
    tuple val(meta), path("*__space-flair_label-WMlesion_desc-lst_mask.nii.gz"), emit: lesion_mask
    tuple val(meta), path("*__mask_lesion_stats.csv")                          , emit: lesion_stats
    tuple val(meta), path("*__space-flair_label-WMlesion_desc-lst_dseg.nii.gz"), emit: lesion_dseg, optional: true
    tuple val(meta), path("*__annotated_lesion_stats.csv")                     , emit: lesion_stats_dseg, optional: true
    path "versions.yml"                                                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def device = task.ext.gpu ? "--device 0" : "--device cpu"
    def nthreads = task.ext.single_thread ? 1 : task.cpus
    def threshold = task.ext.threshold != null ? "--threshold ${task.ext.threshold}" : ""
    def lesion_threshold = task.ext.lesion_threshold != null ? "--lesion_threshold ${task.ext.lesion_threshold}" : ""
    def clipping = task.ext.clipping ? "--clipping ${task.ext.clipping}" : ""
    def stripped = task.ext.stripped ? "--stripped" : ""
    def segment_only = task.ext.segment_only ? "--segment_only" : ""
    def fast_mode = task.ext.fast_mode ? "--fast-mode" : ""

    """
    export OMP_NUM_THREADS=$nthreads
    export MKL_NUM_THREADS=$nthreads
    export OPENBLAS_NUM_THREADS=$nthreads
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$nthreads

    lst \
        $device \
        --t1 $t1 \
        --flair $flair \
        --output lst_output \
        --temp lst_temp \
        --threads $nthreads \
        $threshold \
        $lesion_threshold \
        $clipping \
        $stripped \
        $segment_only \
        $fast_mode

    mv lst_output/space-flair_seg-lst.nii.gz ${prefix}__space-flair_label-WMlesion_desc-lst_mask.nii.gz
    mv lst_output/lesion_stats.csv ${prefix}__mask_lesion_stats.csv

    if [[ -f lst_output/space-flair_desc-annotated_seg-lst.nii.gz ]]; then
        mv lst_output/space-flair_desc-annotated_seg-lst.nii.gz ${prefix}__space-flair_label-WMlesion_desc-lst_dseg.nii.gz
        mv lst_output/annotated_lesion_stats.csv ${prefix}__annotated_lesion_stats.csv
    fi

    rm -rf lst_temp lst_output

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst-ai: \$(pip show lst-ai 2>/dev/null | sed -n 's/^Version: //p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    lst -h

    touch ${prefix}__space-flair_label-WMlesion_desc-lst_mask.nii.gz
    touch ${prefix}__mask_lesion_stats.csv
    if [[ "${task.ext.segment_only ?: false}" != "true" ]]; then
        touch ${prefix}__space-flair_label-WMlesion_desc-lst_dseg.nii.gz
        touch ${prefix}__annotated_lesion_stats.csv
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst-ai: \$(pip show lst-ai 2>/dev/null | sed -n 's/^Version: //p')
    END_VERSIONS
    """
}
