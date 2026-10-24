process SEGMENTATION_LSTAI {
    tag "$meta.id"
    label 'process_high'

    container "${ task.ext.cpu == 'cpu' ?
        "jqmcginnis/lst-ai:v2.0.0rc1-cpu" :
        "jqmcginnis/lst-ai:v2.0.0rc1"}"
    containerOptions((workflow.containerEngine == 'docker') ? '--entrypoint "" --user $(id -u):$(id -g)' : '')

    input:
    tuple val(meta), path(t1), path(flair)

    output:
    tuple val(meta), path("*_space-flair_seg-lst_lesion_mask.nii.gz")                   , emit: lesion_mask
    tuple val(meta), path("*_space-flair_seg-lst_annotated_lesion_mask.nii.gz")         , emit: lesion_mask_annotated, optional: true
    tuple val(meta), path("*_raw_lesion_stats.csv")                                         , emit: lesion_stats, optional: true
    tuple val(meta), path("*_annotated_lesion_stats.csv")                               , emit: lesion_stats_annotated, optional: true
    path "versions.yml"                                                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def device = task.ext.cpu ? "--device ${task.ext.cpu}" : ""
    def threshold = task.ext.threshold ? "--threshold ${task.ext.threshold}" : ""
    def lesion_threshold = task.ext.lesion_threshold ? "--lesion_threshold ${task.ext.lesion_threshold}" : ""
    def clipping = task.ext.clipping ? "--clipping ${task.ext.clipping}" : ""
    def threads = task.ext.single_thread ? "--threads 1" : "--threads ${task.cpus}"
    def stripped = task.ext.skip_stripped ? "--stripped" : ""
    def segment_only = task.ext.segment_only ? "--segment_only" : ""
    def fast_mode = task.ext.fast_mode ? "--fast-mode" : ""

    """
    lst \
        $device \
        --t1 $t1 \
        --flair $flair \
        --output lst_output \
        --temp lst_temp \
        $threshold \
        $lesion_threshold \
        $clipping \
        $threads \
        $stripped \
        $segment_only \
        $fast_mode

    mv lst_output/space-flair_seg-lst.nii.gz ${prefix}_space-flair_seg-lst_lesion_mask.nii.gz
    mv lst_output/lesion_stats.csv ${prefix}_raw_lesion_stats.csv

    if [[ -f lst_output/space-flair_desc-annotated_seg-lst.nii.gz ]]; then
        mv lst_output/space-flair_desc-annotated_seg-lst.nii.gz ${prefix}_space-flair_seg-lst_annotated_lesion_mask.nii.gz
        mv lst_output/annotated_lesion_stats.csv ${prefix}_annotated_lesion_stats.csv
    fi


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst-ai: \$(pip show lst-ai 2>/dev/null | sed -n 's/^Version: //p')
    END_VERSIONS

    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    lst -h

    touch ${prefix}_space-flair_seg-lst_lesion_mask.nii.gz
    touch ${prefix}_space-flair_seg-lst_annotated_lesion_mask.nii.gz
    touch ${prefix}_lesion_stats.csv
    touch ${prefix}_annotated_lesion_stats.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst-ai: \$(pip show lst-ai 2>/dev/null | sed -n 's/^Version: //p')
    END_VERSIONS
    """
}
